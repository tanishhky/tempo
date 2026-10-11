#!/usr/bin/env python3
"""Tempo MCP server: lets an AI assistant read and write your Tempo data.

It speaks MCP over stdio (JSON-RPC, one message per line) and has no dependencies. It reads and
writes the same files as the Mac app, so anything it logs shows up in the ledger and journal.

    sessions.jsonl     one session per line, append-only (the app writes here too)
    activities.json    the list of activities, rewritten atomically
    journal.jsonl      journal checklists, append-only; the last line per (date, activity) wins

Set TEMPO_DATA_DIR to point elsewhere. The default is ~/Library/Application Support/Tempo.

Register it with Claude Code:
    claude mcp add tempo -- python3 /path/to/tempo/tools/tempo_mcp.py
"""

import json
import os
import re
import sys
import tempfile
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path

PROTOCOL_VERSION = "2024-11-05"
SERVER_INFO = {"name": "tempo", "version": "1.1.0"}
COLORS = ["blue", "teal", "green", "amber", "orange", "rose", "violet", "slate"]
KINDS = ("focus", "rest")
MAX_MINUTES = 1440
MAX_NAME = 40
MAX_ITEMS = 100

DEFAULT_ACTIVITIES = [
    {"id": "study", "name": "Study", "kind": "focus", "color": "blue", "checklist": []},
    {"id": "rest", "name": "Rest", "kind": "rest", "color": "teal", "checklist": []},
]


class ToolError(Exception):
    """A problem with the request that the assistant can fix. Returned as a tool error, not a crash."""


def default_data_dir() -> Path:
    env = os.environ.get("TEMPO_DATA_DIR")
    if env:
        return Path(env).expanduser()
    return Path.home() / "Library/Application Support/Tempo"


def utc_iso(moment: datetime) -> str:
    """The format the app's ISO 8601 decoder reads: whole seconds, Z suffix."""
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_iso(text: str) -> datetime:
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


def parse_day(text: str) -> date:
    try:
        return date.fromisoformat(text)
    except (TypeError, ValueError):
        raise ToolError(f"'{text}' is not a date. Use YYYY-MM-DD.")


def local_today() -> date:
    return datetime.now().astimezone().date()


def noon_on(day: date) -> datetime:
    """Noon local time on a day, so a session logged for a past date lands on that date in any timezone."""
    return datetime.combine(day, time(12, 0)).astimezone()


class TempoData:
    """Reads and writes the three Tempo files. Lines are only ever appended, never rewritten."""

    def __init__(self, root: Path):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)

    @property
    def sessions_path(self) -> Path:
        return self.root / "sessions.jsonl"

    @property
    def activities_path(self) -> Path:
        return self.root / "activities.json"

    @property
    def journal_path(self) -> Path:
        return self.root / "journal.jsonl"

    # Activities

    def activities(self) -> list:
        try:
            data = json.loads(self.activities_path.read_text(encoding="utf-8"))
        except (FileNotFoundError, json.JSONDecodeError):
            return [dict(a) for a in DEFAULT_ACTIVITIES]
        found = data.get("activities") if isinstance(data, dict) else None
        return found or [dict(a) for a in DEFAULT_ACTIVITIES]

    def save_activities(self, activities: list) -> None:
        payload = json.dumps({"version": 1, "activities": activities}, indent=2, sort_keys=True) + "\n"
        self._atomic_write(self.activities_path, payload)

    def find_activity(self, ref: str) -> dict:
        if not isinstance(ref, str) or not ref.strip():
            raise ToolError("Name the activity, for example 'Study' or 'quiz'.")
        activities = self.activities()
        for a in activities:
            if a["id"] == ref:
                return a
        matches = [a for a in activities if a["name"].casefold() == ref.strip().casefold()]
        if len(matches) == 1:
            return matches[0]
        if len(matches) > 1:
            ids = ", ".join(a["id"] for a in matches)
            raise ToolError(f"'{ref}' matches more than one activity ({ids}). Use the id.")
        known = ", ".join(a["name"] for a in activities)
        raise ToolError(f"No activity called '{ref}'. Known activities: {known}.")

    def make_id(self, name: str, existing: list) -> str:
        slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "activity"
        taken = {a["id"] for a in existing}
        candidate, n = slug, 2
        while candidate in taken:
            candidate = f"{slug}-{n}"
            n += 1
        return candidate

    # Sessions

    def append_session(self, session: dict) -> None:
        self._append_line(self.sessions_path, session)

    def sessions(self) -> list:
        sessions = []
        for line in self._lines(self.sessions_path):
            try:
                s = json.loads(line)
                start, end = parse_iso(s["start"]), parse_iso(s["end"])
            except (json.JSONDecodeError, KeyError, ValueError, TypeError):
                continue
            s["start"], s["end"] = start, end
            s.setdefault("topic", "")
            s.setdefault("completed", True)
            # Lines from before activities existed have no id. They count as Study or Rest by phase.
            s["activity"] = s.get("activity") or ("rest" if s.get("phase") == "rest" else "study")
            sessions.append(s)
        return sessions

    # Journal

    def append_journal(self, entry: dict) -> None:
        self._append_line(self.journal_path, entry)

    def journal(self) -> dict:
        """Current entry per (date, activity). The last line in the file for a pair wins."""
        current = {}
        for line in self._lines(self.journal_path):
            try:
                entry = json.loads(line)
                current[(entry["date"], entry["activity"])] = entry
            except (json.JSONDecodeError, KeyError, TypeError):
                continue
        return current

    # Files

    def _lines(self, path: Path):
        try:
            return [line for line in path.read_text(encoding="utf-8").split("\n") if line.strip()]
        except FileNotFoundError:
            return []

    def _append_line(self, path: Path, obj: dict) -> None:
        with path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(obj, sort_keys=True) + "\n")

    def _atomic_write(self, path: Path, text: str) -> None:
        fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=path.name + ".", suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                fh.write(text)
            os.replace(tmp, path)
        except BaseException:
            if os.path.exists(tmp):
                os.unlink(tmp)
            raise


# Tools

def tool_list_activities(data: TempoData, args: dict) -> dict:
    return {"activities": data.activities()}


def tool_add_activity(data: TempoData, args: dict) -> dict:
    name = str(args.get("name", "")).strip()
    if not name or len(name) > MAX_NAME:
        raise ToolError(f"Give the activity a name of 1 to {MAX_NAME} characters.")
    kind = args.get("kind")
    if kind not in KINDS:
        raise ToolError("kind must be 'focus' (counts toward the goal) or 'rest'.")
    color = args.get("color", COLORS[0])
    if color not in COLORS:
        raise ToolError(f"color must be one of: {', '.join(COLORS)}.")
    checklist = args.get("checklist", [])
    if not isinstance(checklist, list) or len(checklist) > MAX_ITEMS:
        raise ToolError("checklist must be a list of text items.")
    activities = data.activities()
    activity = {
        "id": data.make_id(name, activities),
        "name": name,
        "kind": kind,
        "color": color,
        "checklist": [str(item).strip() for item in checklist if str(item).strip()],
    }
    data.save_activities(activities + [activity])
    return {"added": activity}


def tool_log_session(data: TempoData, args: dict) -> dict:
    activity = data.find_activity(args.get("activity"))
    minutes = args.get("minutes")
    if not isinstance(minutes, (int, float)) or isinstance(minutes, bool) or not 0 < minutes <= MAX_MINUTES:
        raise ToolError(f"minutes must be a number between 0 and {MAX_MINUTES}.")
    completed = args.get("completed", True)
    if not isinstance(completed, bool):
        raise ToolError("completed must be true or false.")
    day = parse_day(args["date"]) if args.get("date") else local_today()
    today = local_today()
    if day > today:
        raise ToolError("Sessions can't be logged for a future date.")
    end = datetime.now().astimezone() if day == today else noon_on(day)
    start = end - timedelta(minutes=minutes)
    session = {
        "activity": activity["id"],
        "completed": completed,
        "end": utc_iso(end),
        "minutes": round(float(minutes), 2),
        "phase": activity["kind"],
        "start": utc_iso(start),
        "topic": str(args.get("topic", "")).strip(),
    }
    data.append_session(session)
    return {"logged": session, "activity_name": activity["name"]}


def checklist_items(raw) -> list:
    if not isinstance(raw, list) or len(raw) > MAX_ITEMS:
        raise ToolError(f"items must be a list of up to {MAX_ITEMS} entries.")
    items = []
    for item in raw:
        if isinstance(item, str):
            items.append({"text": item.strip(), "done": False})
        elif isinstance(item, dict) and isinstance(item.get("text"), str):
            items.append({"text": item["text"].strip(), "done": bool(item.get("done", False))})
        else:
            raise ToolError("Each item is either a string or {\"text\": ..., \"done\": true|false}.")
    return [i for i in items if i["text"]]


def tool_set_journal(data: TempoData, args: dict) -> dict:
    day = parse_day(args.get("date", ""))
    activity = data.find_activity(args.get("activity"))
    key = (day.isoformat(), activity["id"])
    existing = data.journal().get(key)
    if "items" in args:
        items = checklist_items(args["items"])
    elif existing:
        items = existing["items"]
    else:
        items = [{"text": text, "done": False} for text in activity.get("checklist", [])]
    note = args["note"] if "note" in args else (existing or {}).get("note", "")
    if not isinstance(note, str):
        raise ToolError("note must be text.")
    entry = {"activity": activity["id"], "date": day.isoformat(), "items": items, "note": note.strip()}
    data.append_journal(entry)
    done = sum(1 for i in items if i["done"])
    return {"saved": entry, "progress": f"{done} of {len(items)} done"}


def tool_get_journal(data: TempoData, args: dict) -> dict:
    day = parse_day(args.get("date", ""))
    entries = [e for (d, _), e in data.journal().items() if d == day.isoformat()]
    return {"date": day.isoformat(), "entries": sorted(entries, key=lambda e: e["activity"])}


def tool_summary(data: TempoData, args: dict) -> dict:
    days = args.get("days", 7)
    if not isinstance(days, int) or isinstance(days, bool) or not 1 <= days <= 365:
        raise ToolError("days must be a whole number from 1 to 365.")
    today = local_today()
    first = today - timedelta(days=days - 1)
    activities = {a["id"]: a for a in data.activities()}

    minutes = {}
    logged_days = {}
    focus = rest = 0.0
    for s in data.sessions():
        when = s["end"].astimezone().date()
        logged_days.setdefault(s["activity"], set()).add(when)
        if first <= when <= today:
            minutes[s["activity"]] = minutes.get(s["activity"], 0.0) + s["minutes"]
            if s["phase"] == "rest":
                rest += s["minutes"]
            else:
                focus += s["minutes"]

    rows = []
    for aid in sorted(set(minutes) | set(activities), key=lambda k: -minutes.get(k, 0.0)):
        a = activities.get(aid, {"name": aid, "kind": "focus"})
        in_range = {d for d in logged_days.get(aid, set()) if first <= d <= today}
        rows.append({
            "id": aid,
            "name": a["name"],
            "kind": a["kind"],
            "minutes": round(minutes.get(aid, 0.0), 1),
            "days_logged": len(in_range),
            "logged_in_a_row": streak(logged_days.get(aid, set()), today),
        })
    return {
        "from": first.isoformat(),
        "to": today.isoformat(),
        "focus_minutes": round(focus, 1),
        "rest_minutes": round(rest, 1),
        "activities": rows,
    }


def streak(days: set, today: date) -> int:
    """Consecutive days logged, counting back from today, or from yesterday if today has none yet."""
    cursor = today if today in days else today - timedelta(days=1)
    count = 0
    while cursor in days:
        count += 1
        cursor -= timedelta(days=1)
    return count


def _schema(properties: dict, required: list) -> dict:
    return {"type": "object", "properties": properties, "required": required, "additionalProperties": False}


TOOLS = [
    {
        "name": "tempo_list_activities",
        "description": "List the activities Tempo tracks, each with its id, name, kind (focus or rest) and default checklist.",
        "inputSchema": _schema({}, []),
        "handler": tool_list_activities,
    },
    {
        "name": "tempo_add_activity",
        "description": "Add an activity such as Quiz or Reading. kind 'focus' counts toward the daily goal; 'rest' does not.",
        "inputSchema": _schema({
            "name": {"type": "string", "maxLength": MAX_NAME},
            "kind": {"type": "string", "enum": list(KINDS)},
            "color": {"type": "string", "enum": COLORS},
            "checklist": {"type": "array", "items": {"type": "string"}, "maxItems": MAX_ITEMS},
        }, ["name", "kind"]),
        "handler": tool_add_activity,
    },
    {
        "name": "tempo_log_session",
        "description": "Log time spent on an activity. Use a date (YYYY-MM-DD) to log a past day; omit it for today.",
        "inputSchema": _schema({
            "activity": {"type": "string", "description": "Activity id or name"},
            "minutes": {"type": "number", "exclusiveMinimum": 0, "maximum": MAX_MINUTES},
            "date": {"type": "string", "description": "YYYY-MM-DD, local day"},
            "topic": {"type": "string"},
            "completed": {"type": "boolean"},
        }, ["activity", "minutes"]),
        "handler": tool_log_session,
    },
    {
        "name": "tempo_set_journal",
        "description": "Set the checklist and note for one activity on one day. Omit items to keep the day's current items, "
                       "or to start from the activity's default checklist. Items can be strings or {text, done}.",
        "inputSchema": _schema({
            "date": {"type": "string", "description": "YYYY-MM-DD"},
            "activity": {"type": "string", "description": "Activity id or name"},
            "items": {"type": "array", "maxItems": MAX_ITEMS, "items": {"anyOf": [
                {"type": "string"},
                {"type": "object", "properties": {"text": {"type": "string"}, "done": {"type": "boolean"}},
                 "required": ["text"], "additionalProperties": False},
            ]}},
            "note": {"type": "string"},
        }, ["date", "activity"]),
        "handler": tool_set_journal,
    },
    {
        "name": "tempo_get_journal",
        "description": "Read every journal checklist saved for one day.",
        "inputSchema": _schema({"date": {"type": "string", "description": "YYYY-MM-DD"}}, ["date"]),
        "handler": tool_get_journal,
    },
    {
        "name": "tempo_summary",
        "description": "Time per activity over the last N days, with days logged and the current run of days logged in a row.",
        "inputSchema": _schema({"days": {"type": "integer", "minimum": 1, "maximum": 365}}, []),
        "handler": tool_summary,
    },
]
TOOL_BY_NAME = {t["name"]: t for t in TOOLS}


def call_tool(data: TempoData, name: str, args: dict) -> dict:
    tool = TOOL_BY_NAME.get(name)
    if tool is None:
        raise ToolError(f"Unknown tool '{name}'.")
    return tool["handler"](data, args)


def handle(message: dict, data: TempoData):
    """Answers one JSON-RPC message. Returns None for notifications, which get no reply."""
    if not isinstance(message, dict):
        return error_reply(None, -32600, "Invalid request")
    request_id = message.get("id")
    method = message.get("method")
    params = message.get("params") or {}
    if request_id is None:
        return None  # notifications such as notifications/initialized
    if method == "initialize":
        result = {"protocolVersion": PROTOCOL_VERSION, "capabilities": {"tools": {}}, "serverInfo": SERVER_INFO}
    elif method == "ping":
        result = {}
    elif method == "tools/list":
        result = {"tools": [{k: v for k, v in t.items() if k != "handler"} for t in TOOLS]}
    elif method == "tools/call":
        name = params.get("name", "")
        args = params.get("arguments") or {}
        try:
            payload = call_tool(data, name, args)
            text = json.dumps(payload, indent=2, default=str)
            result = {"content": [{"type": "text", "text": text}], "isError": False}
        except ToolError as problem:
            result = {"content": [{"type": "text", "text": str(problem)}], "isError": True}
    else:
        return error_reply(request_id, -32601, f"Method not found: {method}")
    return {"jsonrpc": "2.0", "id": request_id, "result": result}


def error_reply(request_id, code: int, message: str) -> dict:
    return {"jsonrpc": "2.0", "id": request_id, "error": {"code": code, "message": message}}


def serve(stdin, stdout, data: TempoData) -> None:
    for line in stdin:
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            reply = error_reply(None, -32700, "Parse error")
        else:
            reply = handle(message, data)
        if reply is not None:
            stdout.write(json.dumps(reply) + "\n")
            stdout.flush()


def main() -> None:
    serve(sys.stdin, sys.stdout, TempoData(default_data_dir()))


if __name__ == "__main__":
    main()
