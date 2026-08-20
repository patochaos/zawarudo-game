extends Node
class_name PlaytestTelemetry

## Privacy-friendly playtest telemetry. Events stay in user:// and the latest
## match can be copied from the result screen. No network request is made here.

var enabled: bool = true
var session_id: String = ""
var latest_report: Dictionary = {}
var _match: Dictionary = {}
var _events: Array[Dictionary] = []
var _match_started_ms: int = 0
var _match_number: int = 0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	session_id = "%x-%04x" % [Time.get_unix_time_from_system(), rng.randi_range(0, 65535)]


func begin_match(mode: String, arena: String, ruleset: String, input_name: String) -> void:
	if not enabled:
		_match.clear()
		_events.clear()
		return
	_match_number += 1
	_match_started_ms = Time.get_ticks_msec()
	_match = {
		"schema": 1,
		"build": str(ProjectSettings.get_setting("application/config/version", "dev")),
		"session": session_id,
		"match": _match_number,
		"started_utc": Time.get_datetime_string_from_system(true, true),
		"platform": OS.get_name(),
		"locale": OS.get_locale_language(),
		"mode": mode,
		"arena": arena,
		"ruleset": ruleset,
		"input": input_name,
	}
	_events.clear()
	record("match_started", 1)


func record(name: String, turn: int, data: Dictionary = {}) -> void:
	if not enabled or _match.is_empty():
		return
	_events.append({
		"event": name,
		"turn": turn,
		"ms": Time.get_ticks_msec() - _match_started_ms,
		"data": data.duplicate(true),
	})


func finish_match(winner: int, score: Array[int], turn: int, world_digest: String = "") -> void:
	if not enabled or _match.is_empty():
		return
	record("match_finished", turn, {"winner": winner + 1})
	latest_report = _match.duplicate(true)
	latest_report["duration_ms"] = Time.get_ticks_msec() - _match_started_ms
	latest_report["turns"] = turn
	latest_report["winner"] = winner + 1 if winner >= 0 else 0
	latest_report["score"] = score.duplicate()
	latest_report["events"] = _events.duplicate(true)
	if not world_digest.is_empty():
		latest_report["final_digest"] = world_digest
	_write_latest()
	_append_session_log()


func copy_latest_to_clipboard() -> bool:
	if latest_report.is_empty():
		return false
	DisplayServer.clipboard_set(JSON.stringify(latest_report, "  "))
	return true


func latest_path() -> String:
	return ProjectSettings.globalize_path("user://latest-match-report.json")


func _write_latest() -> void:
	var file := FileAccess.open("user://latest-match-report.json", FileAccess.WRITE)
	if file == null:
		push_warning("Could not write latest playtest report")
		return
	file.store_string(JSON.stringify(latest_report, "  "))


func _append_session_log() -> void:
	var file := FileAccess.open("user://playtest-telemetry.jsonl", FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open("user://playtest-telemetry.jsonl", FileAccess.WRITE)
	if file == null:
		push_warning("Could not append playtest telemetry")
		return
	file.seek_end()
	file.store_line(JSON.stringify(latest_report))
