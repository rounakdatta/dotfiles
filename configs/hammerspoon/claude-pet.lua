-- Claude Code desk-pets
--
-- Two squads of Claude Code bots, both reading the ~/.cache/claude-sessions
-- registry written by the claude-session-tracker hook (see configs/claude):
--
--   * WAITING (orange, top-middle) — one per session that needs you
--     (attention/asking). Peeks in on a rhythm, holds while hovered, can be
--     summoned to the top edge, wears its tmux window name, and clicks through
--     to its pane. A blocked question (asking) bounces hard until answered.
--   * WORKING (grey, top-left, smaller) — one per session currently working.
--     They just hang there and vibrate; an ambient "how many are grinding"
--     count. No label, no click. When a session finishes, its grey working bot
--     vanishes and an orange waiting bot appears — the whole lifecycle at a
--     glance.
--
-- @TMUX@, @LOGO@ and @LOGO_WORKING@ are substituted by Nix at build time.

local TMUX = "@TMUX@"
local LOGO = "@LOGO@"
local LOGO_WORKING = "@LOGO_WORKING@"
local TERMINAL_APP = "kitty" -- frontmost app name that means "you're in the terminal"
local REGISTRY = os.getenv("HOME") .. "/.cache/claude-sessions"
local TTL = 28800 -- ignore sessions stale > 8h

-- Look & feel — tweak freely; the config auto-reloads on the next switch.
local SIZE = 56 -- waiting bot square (px)
local GAP = 10 -- space between bots
local TOP_GAP = 6 -- gap below the menu bar when down
local STEP = 0.03 -- render tick (~33fps)
local EASE = 0.18 -- glide factor toward target
local BOB_AMPL = 3 -- idle bob height, px
local BOB_URGENT = 9 -- bob height for an "asking" bot (Claude blocked on a question)
local BOB_PERIOD = 2.6 -- idle bob period, seconds
local CASCADE = 26 -- per-bot drop-in stagger, px of head start
local SHOW_TIME = 4.0 -- seconds the waiting bots hang before retreating
local HIDE_TIME = 6.0 -- seconds hidden between peeks
local SUMMON_EDGE = 4 -- mouse within this many px of the top edge summons them
-- Working bots (grey, top-left, vibrating).
local WORK_SIZE = 36 -- working bot square (px); smaller than the waiting bots
local WORK_MARGIN = 16 -- gap from the left screen edge
local WORK_ALPHA = 0.72 -- dim the black logo to a grey-black, ambient look
local VIB_AMPL = 2 -- vibrate amplitude, px
local VIB_PERIOD = 0.13 -- vibrate period (~8 Hz buzz)
-- The waiting-bot name, fitted inside the body (fractions of SIZE, below the eyes).
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
local WORK_IMG = hs.image.imageFromPath(LOGO_WORKING)
local BOB_W = 2 * math.pi / BOB_PERIOD
local VIB_W = 2 * math.pi / VIB_PERIOD

local M = { pendants = {}, working = {}, phase = "show", phaseStart = 0 }

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
-- Frame (usable area, below the menu bar) and fullFrame (whole display), or nil
-- transiently during display reconfiguration (sleep/wake, monitor hotplug).
local function screenGeom()
  local screen = hs.screen.mainScreen()
  if not screen then
    return nil
  end
  return screen:frame(), screen:fullFrame()
end

local function slotX(f, n, i) -- waiting bot i (0-based) of n, centered row (top-middle)
  local total = n * SIZE + (n - 1) * GAP
  return f.x + (f.w - total) / 2 + i * (SIZE + GAP)
end

local function workSlotX(f, i) -- working bot i (0-based), left-anchored row (top-left)
  return f.x + WORK_MARGIN + i * (WORK_SIZE + GAP)
end

-- ------------------------------------------------------------- pendants --
-- Waiting bot. Element order: 1 = hover backing, 2 = bot, 3 = label.
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

-- Working bot: just the dimmed grey logo, no label, no interaction.
local function makeWorkingPendant(session, vibPhase, startY)
  local c = hs.canvas.new({ x = 0, y = startY, w = WORK_SIZE, h = WORK_SIZE })
  if WORK_IMG then
    c:appendElements({
      type = "image",
      image = WORK_IMG,
      imageScaling = "scaleProportionally",
      imageAlpha = WORK_ALPHA,
      frame = { x = 0, y = 0, w = WORK_SIZE, h = WORK_SIZE },
    })
  else
    c:appendElements({
      type = "text",
      text = "🤖",
      textSize = WORK_SIZE * 0.5,
      textAlignment = "center",
      frame = { x = 0, y = WORK_SIZE * 0.25, w = WORK_SIZE, h = WORK_SIZE * 0.5 },
    })
  end
  c:level(hs.canvas.windowLevels.overlay)
  c:behaviorAsLabels({ "canJoinAllSpaces", "stationary" })
  c:show()
  return {
    canvas = c,
    session = session,
    vibPhase = vibPhase,
    placed = false,
    curX = 0,
    curY = startY,
    targetX = 0,
    dying = false,
  }
end

-- ------------------------------------------- render + visibility director --
local function tick()
  local t = hs.timer.secondsSinceEpoch()
  local f, full = screenGeom()
  if not f then -- no screen right now; skip this frame
    return
  end
  local hangY = f.y + TOP_GAP

  -- Waiting visibility director: hold down while hovered, summoned (pointer at
  -- top-center edge), or any session is asking; otherwise peek on a rhythm.
  local hovering = false
  for _, p in pairs(M.pendants) do
    if p.hovered then
      hovering = true
    end
  end
  local summon = false
  if hs.mouse.absolutePosition then
    local mp = hs.mouse.absolutePosition()
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

  local any = false

  -- Waiting bots: orange, top-middle, peek + bob.
  local hiddenY = full.y - SIZE - 2
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

  -- Working bots: grey, top-left, always shown while working, vibrating.
  local wHiddenY = full.y - WORK_SIZE - 2
  for sid, p in pairs(M.working) do
    any = true
    local targetY = p.dying and wHiddenY or hangY
    p.curX = p.curX + (p.targetX - p.curX) * EASE
    p.curY = p.curY + (targetY - p.curY) * EASE
    local vx = VIB_AMPL * math.sin(t * VIB_W + p.vibPhase)
    local vy = VIB_AMPL * math.sin(t * VIB_W * 1.7 + p.vibPhase)
    p.canvas:topLeft({ x = p.curX + vx, y = p.curY + vy })
    if p.dying and math.abs(p.curY - wHiddenY) < 1.0 then
      p.canvas:delete()
      M.working[sid] = nil
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
local function byTime(a, b)
  local au, bu = a.updated_at or 0, b.updated_at or 0
  if au ~= bu then
    return au < bu
  end
  return (a.session_id or "") < (b.session_id or "") -- stable order on ties
end

function M.evaluate()
  local active = activePane()
  local now = os.time()
  local waiting, busy = {}, {}
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
    elseif fresh and d.state == "working" then
      table.insert(busy, d)
    end
  end
  table.sort(waiting, byTime)
  table.sort(busy, byTime)

  -- Resolve each waiting session's tmux window name + pane index, and count how
  -- many waiting sessions share a window, so we only disambiguate on collision.
  local winCount = {}
  for _, d in ipairs(waiting) do
    local wname, pidx = windowInfo(d.tmux_pane)
    d._wname = wname or basename(d.cwd) or "claude"
    d._pidx = pidx
    winCount[d._wname] = (winCount[d._wname] or 0) + 1
  end

  local f, full = screenGeom()
  if not f then -- no screen right now; try again on the next evaluate
    return
  end
  local hiddenY = full.y - SIZE - 2
  local wHiddenY = full.y - WORK_SIZE - 2

  -- Reconcile the waiting bots (orange, top-middle).
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

  -- Reconcile the working bots (grey, top-left).
  local wpresent = {}
  for i, d in ipairs(busy) do
    wpresent[d.session_id] = true
    local p = M.working[d.session_id]
    if not p then
      p = makeWorkingPendant(d, (i - 1) * 0.9, wHiddenY)
      M.working[d.session_id] = p
    end
    p.session = d
    p.dying = false
    p.targetX = workSlotX(f, i - 1)
    if not p.placed then
      p.curX = p.targetX
      p.placed = true
    end
  end
  for sid, p in pairs(M.working) do
    if not wpresent[sid] then
      p.dying = true
    end
  end

  if created then -- a new waiting session => peek immediately
    M.phase = "show"
    M.phaseStart = hs.timer.secondsSinceEpoch()
  end
  if next(M.pendants) ~= nil or next(M.working) ~= nil then
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
