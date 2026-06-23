-- Claude Code desk-pets
--
-- One Claude Code bot (the orange pixel creature) per waiting session, along the
-- top-middle of the screen. Reads the ~/.cache/claude-sessions registry written
-- by the claude-session-tracker hook (see configs/claude).
--
-- Interface:
--   * Rhythm   — the bots peek in, hang for SHOW_TIME, retreat, wait HIDE_TIME,
--                and come back. A new waiting session triggers an instant peek.
--   * Reach    — hovering a bot while it's down holds them all down, so you can
--                click without racing the timer.
--   * Summon   — flick the pointer to the very top edge to drop them in on demand.
--   * Named    — the tmux window name shrinks to fit inside the bot's body.
--   * Click    — jump to that session's pane. Clear-on-arrival retracts its bot.
--
-- @TMUX@ and @LOGO@ are substituted by Nix at build time.

local TMUX = "@TMUX@"
local LOGO = "@LOGO@"
local TERMINAL_APP = "kitty" -- frontmost app name that means "you're in the terminal"
local REGISTRY = os.getenv("HOME") .. "/.cache/claude-sessions"
local TTL = 28800 -- ignore sessions stale > 8h

-- Look & feel — tweak freely; the config auto-reloads on the next switch.
local SIZE = 56 -- bot square (px); smaller => more fit across the top
local GAP = 10 -- space between bots
local TOP_GAP = 6 -- gap below the menu bar when down
local STEP = 0.03 -- render tick (~33fps)
local EASE = 0.18 -- glide factor toward target
local BOB_AMPL = 3 -- idle bob height, px
local BOB_URGENT = 9 -- bob height for an "asking" bot (Claude blocked on a question)
local BOB_PERIOD = 2.6 -- idle bob period, seconds
local CASCADE = 26 -- per-bot drop-in stagger, px of head start
local SHOW_TIME = 4.0 -- seconds the bots hang before retreating
local HIDE_TIME = 6.0 -- seconds hidden between peeks
local SUMMON_EDGE = 4 -- mouse within this many px of the top edge summons them
-- The name, fitted inside the bot body (fractions of SIZE, below the eyes).
local LABEL_FONT = math.max(5, math.floor(SIZE * 0.16)) -- max label size; scales with SIZE
local MIN_FONT = math.max(4, math.floor(SIZE * 0.11)) -- floor; below this we trim instead of shrinking
local MONO_RATIO = 0.62 -- monospace advance width per point (slightly conservative)
local LABEL_FONT_NAME = "Menlo-Bold" -- monospace => exact fit math, guaranteed no bleed
local LABEL_X = 0.19
local LABEL_Y = 0.50
local LABEL_W = 0.62
local LABEL_H = 0.20
local LABEL_COLOR = { white = 1.0 }
local HOVER = { red = 0.10, green = 0.10, blue = 0.12, alpha = 0.22 }
local CLEARC = { white = 0, alpha = 0 }

local LOGO_IMG = hs.image.imageFromPath(LOGO)
local BOB_W = 2 * math.pi / BOB_PERIOD

local M = { pendants = {}, phase = "show", phaseStart = 0 }

-- ---------------------------------------------------------------- helpers --
local function basename(p)
  if not p then
    return nil
  end
  return p:match("([^/]+)/?$")
end

-- tmux window name + pane index for a pane (at display time), or nils if gone.
-- One call, tab-separated (a tab can't appear in a tmux window name).
local function windowInfo(pane)
  if not pane or pane == "" then
    return nil, nil
  end
  local out, ok = hs.execute(TMUX .. " display-message -pt '" .. pane .. "' '#{window_name}\t#{pane_index}' 2>/dev/null")
  if not ok or not out then
    return nil, nil
  end
  out = out:gsub("[\r\n]+$", "")
  local name, idx = out:match("^(.-)\t(.*)$")
  if not name then
    name = out
  end
  if name == "" then
    name = nil
  end
  if idx == "" then
    idx = nil
  end
  return name, idx
end

-- Largest font (<= LABEL_FONT, down to MIN_FONT) at which "name .. suffix" fits
-- availW; below the floor, trim the NAME (always keeping the suffix). The label
-- font is monospace, so width = chars * font * MONO_RATIO is exact and the text
-- never bleeds out of the body. Returns (text, fontSize).
local function fitLabel(name, suffix, availW)
  local text = name .. suffix
  if #text == 0 then
    return text, LABEL_FONT
  end
  local font = availW / (#text * MONO_RATIO)
  if font >= LABEL_FONT then
    return text, LABEL_FONT
  end
  if font >= MIN_FONT then
    return text, math.floor(font)
  end
  local maxChars = math.floor(availW / (MIN_FONT * MONO_RATIO))
  local nameBudget = maxChars - #suffix
  if nameBudget < 1 then
    nameBudget = 1
  end
  if #name > nameBudget then
    name = name:sub(1, nameBudget)
  end
  return name .. suffix, MIN_FONT
end

-- ----------------------------------------------- registry (focus-aware) --
local function activePane()
  local front = hs.application.frontmostApplication()
  if not front or front:name() ~= TERMINAL_APP then
    return nil
  end
  local out, ok = hs.execute(TMUX .. " display-message -p '#{pane_id}' 2>/dev/null")
  if not ok or not out then
    return nil
  end
  out = out:gsub("%s+$", "")
  if out == "" then
    return nil
  end
  return out
end

local function readAll()
  local all = {}
  pcall(function()
    for file in hs.fs.dir(REGISTRY) do
      if file:match("%.json$") then
        local p = REGISTRY .. "/" .. file
        local data = hs.json.read(p)
        if data then
          data._path = p
          table.insert(all, data)
        end
      end
    end
  end)
  return all
end

-- Clear-on-arrival: persist a session as "seen" so it stops nagging. The tracker
-- is stateless and writes "attention" on any later Stop, so a session only
-- re-nags if Claude actually produces another turn there. We mutate the record
-- we just read (minus our internal _path) instead of re-listing the schema.
local function markSeen(data)
  data.state = "seen"
  local path = data._path
  data._path = nil
  hs.json.write(data, path, false, true)
end

-- ------------------------------------------------- jump to waiting pane --
local function jump(session)
  local pane = session and session.tmux_pane
  if not pane or pane == "" then
    return
  end
  local cmd = string.format(
    [[
sid="$(%s display-message -pt '%s' '#{session_name}' 2>/dev/null)"
wid="$(%s display-message -pt '%s' '#{window_id}' 2>/dev/null)"
[ -n "$sid" ] && %s switch-client -t "$sid" 2>/dev/null
[ -n "$wid" ] && %s select-window -t "$wid" 2>/dev/null
%s select-pane -t '%s' 2>/dev/null
]],
    TMUX,
    pane,
    TMUX,
    pane,
    TMUX,
    TMUX,
    TMUX,
    pane
  )
  hs.execute(cmd)
  hs.application.launchOrFocus(TERMINAL_APP)
end

-- ----------------------------------------------------------- geometry --
local function geom()
  local screen = hs.screen.mainScreen()
  if not screen then -- nil transiently during display reconfiguration (sleep/wake)
    return nil
  end
  local f = screen:frame()
  local full = screen:fullFrame()
  return f, full.y - SIZE - 2, f.y + TOP_GAP -- frame, hiddenY, hangY
end

local function slotX(f, n, i) -- x for bot i (0-based) of n, centered row (top-middle)
  local total = n * SIZE + (n - 1) * GAP
  return f.x + (f.w - total) / 2 + i * (SIZE + GAP)
end

-- ------------------------------------------------------------- pendant --
-- Element order: 1 = hover backing, 2 = bot, 3 = label (inside the body).
local function makePendant(session, bobPhase, startY)
  local c = hs.canvas.new({ x = 0, y = startY, w = SIZE, h = SIZE })
  c:appendElements({
    type = "rectangle",
    action = "fill",
    fillColor = CLEARC, -- transparent until hovered
    roundedRectRadii = { xRadius = 16, yRadius = 16 },
    frame = { x = 0, y = 0, w = SIZE, h = SIZE },
  })
  if LOGO_IMG then
    c:appendElements({
      type = "image",
      image = LOGO_IMG,
      imageScaling = "scaleProportionally",
      frame = { x = 0, y = 0, w = SIZE, h = SIZE },
    })
  else
    c:appendElements({
      type = "text",
      text = "🤖",
      textSize = SIZE * 0.5,
      textAlignment = "center",
      frame = { x = 0, y = SIZE * 0.25, w = SIZE, h = SIZE * 0.5 },
    })
  end
  c:appendElements({
    type = "text",
    text = "",
    textFont = LABEL_FONT_NAME,
    textSize = LABEL_FONT,
    textColor = LABEL_COLOR,
    textAlignment = "center",
    frame = { x = SIZE * LABEL_X, y = SIZE * LABEL_Y, w = SIZE * LABEL_W, h = SIZE * LABEL_H },
  })
  c:level(hs.canvas.windowLevels.overlay)
  c:behaviorAsLabels({ "canJoinAllSpaces", "stationary" })
  c:clickActivating(false)
  c:canvasMouseEvents(true, true, true) -- down, up, enter/exit

  local pend = {
    canvas = c,
    session = session,
    bobPhase = bobPhase,
    hovered = false,
    placed = false,
    curX = 0,
    curY = startY,
    targetX = 0,
    dying = false,
  }
  c:mouseCallback(function(_, message)
    if message == "mouseUp" then
      jump(pend.session)
      markSeen(pend.session) -- retract this one immediately
      M.evaluate()
    elseif message == "mouseEnter" then
      pend.hovered = true
      c[1].fillColor = HOVER
    elseif message == "mouseExit" then
      pend.hovered = false
      c[1].fillColor = CLEARC
    end
  end)
  c:show()
  return pend
end

-- ------------------------------------------- render + visibility director --
local function tick()
  local t = hs.timer.secondsSinceEpoch()

  -- Hold the bots down while hovered or while the pointer is at the top edge.
  local hovering = false
  for _, p in pairs(M.pendants) do
    if p.hovered then
      hovering = true
    end
  end
  local summon = false
  local screen = hs.screen.mainScreen()
  if screen and hs.mouse.absolutePosition then
    local mp = hs.mouse.absolutePosition()
    local full = screen:fullFrame()
    -- Only the center of the top edge summons, so it doesn't fight the menu
    -- bar (Apple/app menus on the left, status icons on the right).
    summon = mp ~= nil
      and mp.y <= full.y + SUMMON_EDGE
      and mp.x >= full.x + full.w * 0.30
      and mp.x <= full.x + full.w * 0.70
  end

  local anyUrgent = false
  for _, p in pairs(M.pendants) do
    if p.urgent then
      anyUrgent = true
    end
  end

  if hovering or summon or anyUrgent then
    M.phase = "show" -- a pending question keeps them down until you answer
    M.phaseStart = t
  elseif t - M.phaseStart >= (M.phase == "show" and SHOW_TIME or HIDE_TIME) then
    M.phase = (M.phase == "show") and "hide" or "show"
    M.phaseStart = t
  end
  local show = M.phase ~= "hide"

  local _, hiddenY, hangY = geom()
  if not hiddenY then -- no screen right now; skip this frame
    return
  end
  local any = false
  for sid, p in pairs(M.pendants) do
    any = true
    local targetY = (p.dying or not show) and hiddenY or hangY
    p.curX = p.curX + (p.targetX - p.curX) * EASE
    p.curY = p.curY + (targetY - p.curY) * EASE
    local bob = (p.urgent and BOB_URGENT or BOB_AMPL) * math.sin(t * BOB_W + p.bobPhase)
    p.canvas:topLeft({ x = p.curX, y = p.curY + bob })
    if p.dying and math.abs(p.curY - hiddenY) < 1.0 then
      p.canvas:delete()
      M.pendants[sid] = nil
    end
  end
  if not any and M.render then
    M.render:stop()
    M.render = nil
  end
end

local function ensureRender()
  if not M.render then
    M.render = hs.timer.doEvery(STEP, tick)
  end
end

-- ------------------------------------------------------------- main loop --
function M.evaluate()
  local active = activePane()
  local now = os.time()
  local waiting = {}
  for _, d in ipairs(readAll()) do
    local fresh = type(d.updated_at) == "number" and (now - d.updated_at) < TTL
    if fresh and d.state == "asking" then
      -- A blocked question: always notify, even in the focused pane, and don't
      -- clear it on arrival — it clears when you actually answer (PostToolUse).
      d._urgent = true
      table.insert(waiting, d)
    elseif fresh and d.state == "attention" then
      if active and d.tmux_pane == active then
        markSeen(d) -- clear-on-arrival: you're on it now
      else
        table.insert(waiting, d)
      end
    end
  end
  table.sort(waiting, function(a, b)
    local au, bu = a.updated_at or 0, b.updated_at or 0
    if au ~= bu then
      return au < bu
    end
    return (a.session_id or "") < (b.session_id or "") -- stable order on ties
  end)

  -- Resolve each waiting session's tmux window name + pane index, and count how
  -- many waiting sessions share a window, so we only disambiguate on collision.
  local winCount = {}
  for _, d in ipairs(waiting) do
    local wname, pidx = windowInfo(d.tmux_pane)
    d._wname = wname or basename(d.cwd) or "claude"
    d._pidx = pidx
    winCount[d._wname] = (winCount[d._wname] or 0) + 1
  end

  local f, hiddenY = geom()
  if not f then -- no screen right now; try again on the next evaluate
    return
  end
  local n = #waiting
  local present, created = {}, false
  for i, d in ipairs(waiting) do
    present[d.session_id] = true
    local p = M.pendants[d.session_id]
    if not p then
      p = makePendant(d, (i - 1) * 0.7, hiddenY - (i - 1) * CASCADE)
      M.pendants[d.session_id] = p
      created = true
    end
    p.session = d
    p.urgent = d._urgent == true
    p.dying = false
    p.targetX = slotX(f, n, i - 1)
    if not p.placed then
      p.curX = p.targetX -- snap horizontally on first placement
      p.placed = true
    end
    -- "nix" when alone in its window; "nix (2)" (the pane index) when it shares.
    -- Shrinks the font to fit rather than truncating; trims only as a last resort.
    local suffix = (winCount[d._wname] >= 2 and d._pidx) and (" (" .. d._pidx .. ")") or ""
    local text, font = fitLabel(d._wname, suffix, SIZE * LABEL_W)
    p.canvas[3].text = text
    p.canvas[3].textSize = font
  end

  for sid, p in pairs(M.pendants) do
    if not present[sid] then
      p.dying = true
    end
  end

  if created then -- a new session => peek immediately
    M.phase = "show"
    M.phaseStart = hs.timer.secondsSinceEpoch()
  end
  if next(M.pendants) ~= nil then
    ensureRender()
  end
end

hs.execute("/bin/mkdir -p '" .. REGISTRY .. "'")
M.watcher = hs.pathwatcher.new(REGISTRY, M.evaluate)
if M.watcher then
  M.watcher:start()
end
M.poll = hs.timer.doEvery(3, M.evaluate) -- re-check on focus changes / TTL expiry

-- Auto-reload when this config changes (e.g. after a darwin-rebuild switch).
M.config = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", function(files)
  for _, file in ipairs(files) do
    if file:match("init%.lua$") then
      hs.reload()
      return
    end
  end
end)
if M.config then
  M.config:start()
end

M.evaluate()
