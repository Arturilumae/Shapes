extends "res://Scripts/game.gd"
## Tutorial level: freezes the song right before the first right-arrow,
## left-arrow, hop-left and hop-right transitions until the player presses
## the correct key once. After that the chart plays on normally.

@export var forgiving := true                 # no health drain in the tutorial
@export_file("*.tscn") var next_scene := "res://Scenes/LevelSelect.tscn"   # optional: scene to load after finishing

@export_group("Tekstikast")
@export var tutorial_label: Label             # lohista siia TutorialLabel
@export var tutorial_box: Control             # lohista siia TutorialBox
@export var done_text_time := 2.0             # mitu sekundit "done" tekst nähtav on

const ALL_ACTIONS := ["ui_left", "ui_right", "hop_left", "hop_right"]

# key = "<kind>_<direction>" of a transition
const LESSONS := {
	"diag_right": {"action": "ui_right",  "title": "Right arrow",
		"text": "The line bends to the right.\nPress [%s] to slide along it.",
		"done": "Nice! Arrows slide along diagonals."},
	"diag_left":  {"action": "ui_left",   "title": "Left arrow",
		"text": "The line bends to the left.\nPress [%s] to slide along it.",
		"done": "Great! Well done!"},
	"hop_left":   {"action": "hop_left",  "title": "Hop left",
		"text": "A sharp step to the left!\nPress [%s] to hop.",
		"done": "Hops are instant, so time them carefully."},
	"hop_right":  {"action": "hop_right", "title": "Hop right",
		"text": "A sharp step to the right!\nPress [%s] to hop.",
		"done": "That's every move! Keep going."},
}

var frozen := false
var required_action := ""
var current_key := ""
var taught := {}              # lessons already shown
var tutorial_done := false
var label: Label
var box: Control


func _ready() -> void:
	if forgiving:
		health_drain_rate = 0.0
	super()
	label = _get_or_make_label()
	box = tutorial_box if tutorial_box else get_node_or_null("%TutorialBox") as Control
	_set_text("Get ready…\nFollow the line with the needle.")


func _process(delta: float) -> void:
	if tutorial_done:
		return
	if frozen:
		_update_hud()
		return
	if not playing:
		return
	super(delta)
	if not frozen:
		_check_freeze()
	if song_time > song_end + 0.5:
		_finish()


## While frozen, only the requested key gets through to player.gd.
func _input(event: InputEvent) -> void:
	if not frozen:
		return
	if event.is_action_pressed(required_action):
		return
	for a in ALL_ACTIONS:
		if event.is_action_pressed(a):
			get_viewport().set_input_as_handled()
			return


#region Freezing

func _transition_key(tr: Dictionary) -> String:
	var dir := "right" if tr["to"] > tr["from"] else "left"
	return "%s_%s" % [tr["kind"], dir]


func _check_freeze() -> void:
	for i in range(next_trans, transitions.size()):
		var tr: Dictionary = transitions[i]
		if tr["t"] > song_time:
			break
		if tr["done"]:
			continue
		var key := _transition_key(tr)
		if taught.has(key):
			continue
		_freeze(key, tr)
		return


func _freeze(key: String, tr: Dictionary) -> void:
	frozen = true
	current_key = key
	taught[key] = true
	required_action = LESSONS[key]["action"]

	# Stop exactly on the ideal moment, so the press counts as 100%
	song_time = tr["t"]
	track.position.y = roundi(hit_line_y + dist_at(song_time))
	if use_music:
		music.stream_paused = true

	# Put the needle on the lane the line is leaving, so the move is possible
	player.snap_to_lane(tr["from"])
	player.set_process(false)   # no held-arrow auto-moves while waiting

	var lesson: Dictionary = LESSONS[key]
	_set_text("%s\n%s" % [lesson["title"], lesson["text"] % _key_name(required_action)])


func _unfreeze() -> void:
	frozen = false
	if use_music:
		music.stream_paused = false
	player.set_process(true)
	_set_text(LESSONS[current_key]["done"], done_text_time)


## Grading stays in game.gd; we only resume once the required move was started.
func _on_player_move_started(from_lane: int, to_lane: int, type: String) -> void:
	super(from_lane, to_lane, type)
	if frozen:
		_unfreeze()

#endregion


#region Helpers

## Näitab teksti kastis. Tühi tekst peidab kasti.
## hide_after > 0: peida tekst nii mitme sekundi pärast (kui vahepeal uut teksti pole tulnud).
func _set_text(t: String, hide_after := 0.0) -> void:
	label.text = t
	if box:
		box.visible = t != ""
	else:
		label.visible = t != ""
	if hide_after > 0.0:
		await get_tree().create_timer(hide_after).timeout
		if label.text == t and not frozen:
			_set_text("")


func _key_name(action: String) -> String:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return e.as_text().get_slice(" (", 0)
	return action


func _get_or_make_label() -> Label:
	if tutorial_label:
		return tutorial_label
	var l := get_node_or_null("%TutorialLabel") as Label
	if l:
		return l
	# varuvariant, kui stseenis kasti pole
	push_warning("TutorialLabel'it ei leitud, teen ajutise Labeli.")
	l = Label.new()
	l.name = "TutorialLabel"
	l.position = Vector2(4, 4)
	l.size = Vector2(play_width - 8, 40)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.z_index = 200
	add_child(l)
	return l


func _finish() -> void:
	tutorial_done = true
	playing = false
	if use_music:
		music.stop()
	_set_text("Tutorial complete!\nAccuracy %d%%" % int(accuracy_percent()))
	if next_scene != "":
		await get_tree().create_timer(3.0).timeout
		get_tree().change_scene_to_file(next_scene)

#endregion
