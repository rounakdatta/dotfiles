#!/usr/bin/env python3
"""Turn everyday date/time phrases into RFC3339 timestamps in Asia/Kolkata.

Why this exists: festie ships no /usr/share/zoneinfo and sets no TZDIR, so
coreutils `date` silently ignores `TZ=Asia/Kolkata` and answers in UTC --
`TZ=Asia/Kolkata date -d 'tomorrow 12:30'` prints a +00:00 offset and looks
entirely plausible. Every task created that way lands 5h30m late. Python's
zoneinfo finds tzdata through the Nix store, so all date maths goes through
here instead of through `date`.

Usage:
    vikunja-when 'tomorrow 12:30pm'
    vikunja-when 'next monday 9am'
    vikunja-when now
    vikunja-when 'in 2 hours'
    vikunja-when --date 'friday'          # date only, midnight IST
"""
import argparse
import re
import sys
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

IST = ZoneInfo("Asia/Kolkata")
WEEKDAYS = {
    "monday": 0, "mon": 0, "tuesday": 1, "tue": 1, "tues": 1,
    "wednesday": 2, "wed": 2, "thursday": 3, "thu": 3, "thurs": 3,
    "friday": 4, "fri": 4, "saturday": 5, "sat": 5, "sunday": 6, "sun": 6,
}
# Vague times get a concrete convention rather than a guess at call time.
NAMED_TIMES = {
    "morning": (9, 0), "noon": (12, 0), "midday": (12, 0),
    "afternoon": (15, 0), "evening": (18, 0), "night": (21, 0),
    "midnight": (0, 0), "eod": (18, 0), "cob": (18, 0),
}


def parse_time(text):
    """Return ((hour, minute), leftover_text) or (None, text)."""
    # 12:30pm / 12.30 pm / 1230pm / 9am / 09:00
    m = re.search(
        r"\b(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)\b", text, re.I)
    if m:
        h, mi = int(m.group(1)), int(m.group(2) or 0)
        mer = m.group(3).replace(".", "").lower()
        if mer == "am":
            h = 0 if h == 12 else h
        else:
            h = h if h == 12 else h + 12
        return (h, mi), text[: m.start()] + text[m.end():]
    # 24h with explicit colon, e.g. 18:45 -- require the colon so a bare
    # "25" in "25 august" is never mistaken for 25:00.
    m = re.search(r"\b(\d{1,2}):(\d{2})\b", text)
    if m:
        return (int(m.group(1)), int(m.group(2))), text[: m.start()] + text[m.end():]
    for name, hm in NAMED_TIMES.items():
        if re.search(rf"\b{name}\b", text, re.I):
            return hm, re.sub(rf"\b{name}\b", "", text, flags=re.I)
    return None, text


def resolve(phrase, now, date_only=False):
    s = phrase.strip().lower()

    # Already a timestamp? Trust it, but make sure it carries an offset.
    try:
        dt = datetime.fromisoformat(phrase.strip())
        return dt if dt.tzinfo else dt.replace(tzinfo=IST)
    except ValueError:
        pass

    if s in ("now",):
        return now

    # "in 2 hours" / "in 30 minutes" / "in 3 days" / "in 2 weeks"
    m = re.fullmatch(r"in\s+(\d+)\s*(min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days|w|week|weeks)", s)
    if m:
        n, unit = int(m.group(1)), m.group(2)
        if unit.startswith(("min",)):
            return now + timedelta(minutes=n)
        if unit.startswith(("h",)):
            return now + timedelta(hours=n)
        if unit.startswith(("d",)):
            return now + timedelta(days=n)
        return now + timedelta(weeks=n)

    tod, rest = parse_time(s)
    rest = " ".join(rest.split())

    base = None
    if rest in ("", "today"):
        base = now.date()
    elif rest == "tomorrow" or rest == "tmrw":
        base = now.date() + timedelta(days=1)
    elif rest == "yesterday":
        base = now.date() - timedelta(days=1)
    elif rest in ("day after tomorrow", "overmorrow"):
        base = now.date() + timedelta(days=2)
    else:
        m = re.fullmatch(r"(?:(next|this|coming)\s+)?(\w+)", rest)
        if m and m.group(2) in WEEKDAYS:
            target = WEEKDAYS[m.group(2)]
            delta = (target - now.weekday()) % 7
            # Bare/`this` weekday means the next such day; today only counts
            # when a time later than now was given.
            if delta == 0 and not (tod and (tod[0], tod[1]) > (now.hour, now.minute)):
                delta = 7
            if m.group(1) == "next" and delta < 7:
                # "next monday" when today is Sunday should not mean tomorrow.
                delta += 7 if delta != 0 else 0
            base = now.date() + timedelta(days=delta)
        else:
            # Explicit dates: 25 aug, aug 25, 25/08, 2026-08-25
            dated = [("%Y-%m-%d", rest), ("%d/%m/%Y", rest),
                     ("%d %b %Y", rest), ("%d %B %Y", rest)]
            # Year-less forms: append the current year so strptime never has to
            # fall back on 1900 (which warns, and cannot represent Feb 29).
            yearless = [("%d %b %Y", f"{rest} {now.year}"),
                        ("%d %B %Y", f"{rest} {now.year}"),
                        ("%b %d %Y", f"{rest} {now.year}"),
                        ("%B %d %Y", f"{rest} {now.year}"),
                        ("%d/%m/%Y", f"{rest}/{now.year}"),
                        ("%d-%m-%Y", f"{rest}-{now.year}")]
            for fmt, text in dated + yearless:
                try:
                    base = datetime.strptime(text, fmt).date()
                    break
                except ValueError:
                    continue

    if base is None:
        raise SystemExit(f"vikunja-when: cannot understand {phrase!r}")

    if date_only:
        tod = tod or (0, 0)
    elif tod is None:
        raise SystemExit(
            f"vikunja-when: {phrase!r} has no time of day. Pass --date for "
            "midnight, or ask the user which time they meant.")
    return datetime(base.year, base.month, base.day, tod[0], tod[1], tzinfo=IST)


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("phrase", nargs="+")
    ap.add_argument("--date", action="store_true",
                    help="date-only phrase; default the time to midnight IST")
    ap.add_argument("--utc", action="store_true",
                    help="emit the same instant as UTC (what Vikunja stores)")
    ap.add_argument("--now", help="override 'now' (ISO, for tests)")
    ap.add_argument("--render", action="store_true",
                    help="reverse direction: read a stored Vikunja timestamp "
                         "(UTC) and print it as friendly IST for the user")
    a = ap.parse_args()

    if a.render:
        raw = " ".join(a.phrase).strip().replace("Z", "+00:00")
        dt = datetime.fromisoformat(raw)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=ZoneInfo("UTC"))
        # Vikunja writes this sentinel for "no date set".
        if dt.year <= 1:
            print("(no date)")
            return
        local = dt.astimezone(IST)
        print(local.strftime("%a %d %b %Y, %-I:%M %p IST"))
        return
    now = (datetime.fromisoformat(a.now).replace(tzinfo=IST)
           if a.now else datetime.now(IST))
    dt = resolve(" ".join(a.phrase), now, a.date)
    if a.utc:
        print(dt.astimezone(ZoneInfo("UTC")).strftime("%Y-%m-%dT%H:%M:%SZ"))
    else:
        off = dt.strftime("%z")
        print(dt.strftime("%Y-%m-%dT%H:%M:%S") + off[:3] + ":" + off[3:])


if __name__ == "__main__":
    main()
