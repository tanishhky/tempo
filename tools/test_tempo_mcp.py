"""Tests for the Tempo MCP server. Each test uses a temporary data folder, never your real Tempo files."""

import io
import json
import re
import sys
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import tempo_mcp as mcp  # noqa: E402


class Base(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.data = mcp.TempoData(Path(self._tmp.name))

    def tearDown(self):
        self._tmp.cleanup()

    def call(self, tool, **arguments):
        """Calls a tool the way an MCP client would and returns the decoded payload."""
        reply = mcp.handle({"jsonrpc": "2.0", "id": 1, "method": "tools/call",
                            "params": {"name": tool, "arguments": arguments}}, self.data)
        result = reply["result"]
        text = result["content"][0]["text"]
        if result["isError"]:
            raise ToolFailure(text)
        return json.loads(text)


class ToolFailure(Exception):
    pass


class ActivityTests(Base):
    def test_defaults_when_no_file(self):
        ids = [a["id"] for a in self.call("tempo_list_activities")["activities"]]
        self.assertEqual(ids, ["study", "rest"])

    def test_add_activity_gets_a_unique_slug(self):
        self.call("tempo_add_activity", name="Quiz", kind="focus")
        second = self.call("tempo_add_activity", name="Quiz", kind="focus")
        self.assertEqual(second["added"]["id"], "quiz-2")
        names = [a["name"] for a in self.call("tempo_list_activities")["activities"]]
        self.assertEqual(names, ["Study", "Rest", "Quiz", "Quiz"])

    def test_add_activity_rejects_a_bad_kind(self):
        with self.assertRaises(ToolFailure):
            self.call("tempo_add_activity", name="Walk", kind="exercise")

    def test_activity_can_be_found_by_name_in_any_case(self):
        self.call("tempo_add_activity", name="Quiz", kind="focus")
        logged = self.call("tempo_log_session", activity="QUIZ", minutes=20)
        self.assertEqual(logged["logged"]["activity"], "quiz")

    def test_unknown_activity_lists_the_known_ones(self):
        with self.assertRaisesRegex(ToolFailure, "Known activities: Study, Rest"):
            self.call("tempo_log_session", activity="Chess", minutes=10)

    def test_saved_file_is_valid_json_that_the_app_reads(self):
        self.call("tempo_add_activity", name="Reading", kind="focus", checklist=["Chapter 3"])
        saved = json.loads(self.data.activities_path.read_text())
        self.assertEqual(saved["version"], 1)
        reading = [a for a in saved["activities"] if a["id"] == "reading"][0]
        self.assertEqual(reading["checklist"], ["Chapter 3"])
        self.assertEqual(reading["color"], "blue")


class SessionTests(Base):
    def test_log_writes_an_app_compatible_line(self):
        self.call("tempo_log_session", activity="Study", minutes=45, topic="Options")
        line = json.loads(self.data.sessions_path.read_text().strip())
        self.assertEqual(line["phase"], "focus")
        self.assertEqual(line["activity"], "study")
        self.assertEqual(line["minutes"], 45)
        self.assertEqual(line["topic"], "Options")
        stamp = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
        self.assertRegex(line["start"], stamp)
        self.assertRegex(line["end"], stamp)

    def test_rest_activity_logs_as_rest_phase(self):
        self.call("tempo_log_session", activity="rest", minutes=15)
        line = json.loads(self.data.sessions_path.read_text().strip())
        self.assertEqual(line["phase"], "rest")

    def test_rejects_minutes_out_of_range(self):
        for bad in (0, -5, 1441, "20"):
            with self.subTest(minutes=bad), self.assertRaises(ToolFailure):
                self.call("tempo_log_session", activity="study", minutes=bad)

    def test_rejects_future_dates(self):
        tomorrow = (datetime.now().astimezone().date() + timedelta(days=1)).isoformat()
        with self.assertRaisesRegex(ToolFailure, "future"):
            self.call("tempo_log_session", activity="study", minutes=10, date=tomorrow)

    def test_past_date_lands_on_that_day(self):
        past = (datetime.now().astimezone().date() - timedelta(days=10)).isoformat()
        self.call("tempo_log_session", activity="study", minutes=30, date=past)
        summary = self.call("tempo_summary", days=7)
        self.assertEqual(summary["focus_minutes"], 0)
        longer = self.call("tempo_summary", days=30)
        self.assertEqual(longer["focus_minutes"], 30)


class JournalTests(Base):
    def test_default_checklist_seeds_the_day(self):
        self.call("tempo_add_activity", name="Quiz", kind="focus", checklist=["MCQ 1-20", "Review misses"])
        today = datetime.now().astimezone().date().isoformat()
        saved = self.call("tempo_set_journal", date=today, activity="Quiz", note="warm-up")
        self.assertEqual([i["text"] for i in saved["saved"]["items"]], ["MCQ 1-20", "Review misses"])
        self.assertEqual(saved["progress"], "0 of 2 done")

    def test_last_entry_wins_and_items_are_kept_when_omitted(self):
        self.call("tempo_add_activity", name="Quiz", kind="focus", checklist=["MCQ"])
        today = datetime.now().astimezone().date().isoformat()
        self.call("tempo_set_journal", date=today, activity="quiz",
                  items=[{"text": "MCQ", "done": True}])
        updated = self.call("tempo_set_journal", date=today, activity="quiz", note="solid day")
        self.assertEqual(updated["saved"]["items"], [{"text": "MCQ", "done": True}])
        self.assertEqual(updated["saved"]["note"], "solid day")
        day = self.call("tempo_get_journal", date=today)
        self.assertEqual(len(day["entries"]), 1)
        self.assertEqual(day["entries"][0]["note"], "solid day")

    def test_bad_date_is_a_tool_error(self):
        with self.assertRaisesRegex(ToolFailure, "YYYY-MM-DD"):
            self.call("tempo_get_journal", date="10/11/2026")

    def test_item_must_be_text_or_object(self):
        with self.assertRaises(ToolFailure):
            self.call("tempo_set_journal", date="2026-10-11", activity="study", items=[42])


class SummaryTests(Base):
    def test_summary_splits_minutes_and_counts_streaks(self):
        self.call("tempo_add_activity", name="Quiz", kind="focus")
        today = datetime.now().astimezone().date()
        for back in (0, 1, 2):
            self.call("tempo_log_session", activity="quiz", minutes=30,
                      date=(today - timedelta(days=back)).isoformat())
        self.call("tempo_log_session", activity="rest", minutes=10)
        summary = self.call("tempo_summary", days=7)
        quiz = [a for a in summary["activities"] if a["id"] == "quiz"][0]
        self.assertEqual(quiz["minutes"], 90)
        self.assertEqual(quiz["days_logged"], 3)
        self.assertEqual(quiz["logged_in_a_row"], 3)
        self.assertEqual(summary["focus_minutes"], 90)
        self.assertEqual(summary["rest_minutes"], 10)

    def test_old_sessions_without_an_activity_still_count(self):
        now = datetime.now().astimezone()
        legacy = {"completed": True, "end": mcp.utc_iso(now), "minutes": 50, "phase": "focus",
                  "start": mcp.utc_iso(now - timedelta(minutes=50)), "topic": "Options"}
        self.data.append_session(legacy)
        summary = self.call("tempo_summary", days=1)
        study = [a for a in summary["activities"] if a["id"] == "study"][0]
        self.assertEqual(study["minutes"], 50)

    def test_streak_starts_from_yesterday_when_today_is_empty(self):
        today = datetime.now().astimezone().date()
        days = {today - timedelta(days=1), today - timedelta(days=2)}
        self.assertEqual(mcp.streak(days, today), 2)
        self.assertEqual(mcp.streak(set(), today), 0)

    def test_days_must_be_in_range(self):
        with self.assertRaises(ToolFailure):
            self.call("tempo_summary", days=0)


class ProtocolTests(Base):
    def test_initialize_reports_the_tools_capability(self):
        reply = mcp.handle({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}, self.data)
        self.assertEqual(reply["result"]["serverInfo"]["name"], "tempo")
        self.assertIn("tools", reply["result"]["capabilities"])

    def test_tools_list_names_every_tool_without_handlers(self):
        reply = mcp.handle({"jsonrpc": "2.0", "id": 2, "method": "tools/list"}, self.data)
        names = [t["name"] for t in reply["result"]["tools"]]
        self.assertEqual(names, [t["name"] for t in mcp.TOOLS])
        self.assertNotIn("handler", reply["result"]["tools"][0])

    def test_notifications_get_no_reply(self):
        self.assertIsNone(mcp.handle({"jsonrpc": "2.0", "method": "notifications/initialized"}, self.data))

    def test_unknown_method_is_a_protocol_error(self):
        reply = mcp.handle({"jsonrpc": "2.0", "id": 3, "method": "nope"}, self.data)
        self.assertEqual(reply["error"]["code"], -32601)

    def test_serve_handles_a_line_stream_and_bad_json(self):
        requests = "\n".join([
            json.dumps({"jsonrpc": "2.0", "id": 1, "method": "ping"}),
            "{not json",
            json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}),
            "",
        ])
        out = io.StringIO()
        mcp.serve(io.StringIO(requests), out, self.data)
        replies = [json.loads(line) for line in out.getvalue().splitlines()]
        self.assertEqual(replies[0]["result"], {})
        self.assertEqual(replies[1]["error"]["code"], -32700)
        self.assertEqual(len(replies), 2)


if __name__ == "__main__":
    unittest.main()
