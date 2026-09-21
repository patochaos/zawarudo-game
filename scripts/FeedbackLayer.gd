extends CanvasLayer

const EMAIL := "patochaos@gmail.com"
var gm
var _notes: TextEdit
var _status: Label
var _include: CheckBox

func _ready() -> void:
	layer = 30
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.01, 0.04, 0.98)
	backdrop.size = Vector2(1280, 720)
	add_child(backdrop)
	_label(Vector2(160, 65), Vector2(960, 50), "HELP SHAPE THE NEXT DUEL", 30)
	_label(Vector2(160, 128), Vector2(960, 88),
		"What were you trying to do? What surprised or confused you?\nDid you want another match — and why?", 22)
	_notes = TextEdit.new()
	_notes.position = Vector2(160, 236)
	_notes.size = Vector2(960, 220)
	_notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_notes.placeholder_text = "Your feedback…"
	_notes.add_theme_font_override("font", preload("res://assets/fonts/AtkinsonHyperlegible-Regular.ttf"))
	_notes.add_theme_font_size_override("font_size", 22)
	add_child(_notes)
	_include = CheckBox.new()
	_include.position = Vector2(160, 478)
	_include.text = "Include the latest local match report"
	_include.button_pressed = true
	add_child(_include)
	_button(Vector2(160, 536), "OPEN EMAIL DRAFT", open_email)
	_button(Vector2(490, 536), "COPY FEEDBACK", copy_feedback)
	_button(Vector2(820, 536), "BACK", close)
	_status = _label(Vector2(160, 610), Vector2(960, 70), "", 18)
	visible = false

func _label(at: Vector2, dimensions: Vector2, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.size = dimensions
	label.text = text
	label.add_theme_font_override("font", preload("res://assets/fonts/AtkinsonHyperlegible-Regular.ttf"))
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)
	return label

func _button(at: Vector2, text: String, action: Callable) -> void:
	var button := Button.new()
	button.position = at
	button.size = Vector2(300, 52)
	button.text = text
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(action)
	add_child(button)

func open() -> void:
	# Feedback opens only outside a live turn; it never pauses the match clock.
	if gm.state not in [Phase.MENU, Phase.GAME_OVER]: return
	visible = true
	_status.text = "To %s. Nothing is sent automatically. No email app? Copy feedback and paste it into webmail." % EMAIL
	_notes.grab_focus()

func close() -> void:
	visible = false
	_notes.release_focus()

func feedback_text() -> String:
	var text := "Za Warudo %s\nDevice: %s\n\n%s" % [
		ProjectSettings.get_setting("application/config/version", "dev"), OS.get_name(), _notes.text.strip_edges()]
	if _include.button_pressed and not gm._telemetry.latest_report.is_empty():
		text += "\n\nMatch report:\n" + JSON.stringify(gm._telemetry.latest_report)
	return text

func copy_feedback() -> void:
	DisplayServer.clipboard_set(feedback_text())
	_status.text = "Feedback copied. Paste it into an email to %s." % EMAIL

func email_uri() -> String:
	# Keep mailto short and reliable; the complete report is copied separately.
	var body := _notes.text.strip_edges().left(1000)
	body += "\n\nBuild: " + str(ProjectSettings.get_setting("application/config/version", "dev"))
	if _include.button_pressed and not gm._telemetry.latest_report.is_empty():
		body += "\n\n[Paste the copied feedback and match report here.]"
	return "mailto:%s?subject=%s&body=%s" % [EMAIL, "Za Warudo playtest feedback".uri_encode(), body.uri_encode()]

func open_email() -> void:
	DisplayServer.clipboard_set(feedback_text())
	var error := OS.shell_open(email_uri())
	_status.text = "Email draft requested. Paste the copied report into your draft before sending." if error == OK else "Could not open an email app. Feedback is copied; paste it into webmail and send to %s." % EMAIL
