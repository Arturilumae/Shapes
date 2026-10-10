extends Node2D

## Salvestusrežiim: laul mängib, sina liigud ringiga radade vahel,
## ja iga raja vahetus salvestatakse chart'iks samas formaadis, mida game.gd loeb.
## Nooled = tavaline (tween) liikumine, Q/E = hüpe ("hop": true).
##
## Tühik = alusta, Esc = lõpeta ja salvesta (salvestab ka laulu lõppedes ise).

@export var song_path := "res://levels/demo/song.ogg"
@export var bpm := 95.65        # laulu BPM (nt Pythoni skripti väljundist)
@export var offset := 0.604         # esimese löögi aeg sekundites
@export var snap := 0.5           # mitme löögi täpsusega ümardatakse (1, 0.5, 0.25)
@export var start_beat := 4.0     # varasemad liigutused jäetakse välja
@export var reaction := 0.05      # sinu reaktsiooniaeg sekundites, lahutatakse maha
@export var output_path := "res://levels/demo/chart_recorded.json"

@export_group("Mängija jaoks (sama mis game.gd-s)")
@export var lane_x0 := 26         # esimese raja keskjoone x
@export var lane_spacing := 52    # kahe raja keskjoonte vahe
@export var hit_line_y := 120     # mängija y
@export var scroll_speed := 110.0 # tween kestab sama kaua kui mängus

@onready var music: AudioStreamPlayer = $Music
@onready var player = $Player
@onready var label: Label = $Label

var changes: Array = []   # iga raja vahetus: {beat, lane, hop}
var last_lane := -1
var current_beat := 0.0
var recording := false


func _ready() -> void:
	music.stream = load(song_path)
	if music.stream == null:
		label.text = "Laulu ei leitud: " + song_path
		return
	music.finished.connect(save_chart)
	player.move_started.connect(_on_move_started)
	label.text = "Tühik = alusta salvestamist"


# ---------- Mängija jaoks (player.gd küsib need vanemsõlmelt) ----------

func lane_x(lane: int) -> int:
	return lane_x0 + lane_spacing * lane


func current_speed() -> float:
	return scroll_speed


# ---------- Salvestamine ----------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not recording and music.stream != null:
		start()
	elif event.is_action_pressed("ui_cancel") and recording:
		music.stop()
		save_chart()


func start() -> void:
	changes.clear()
	current_beat = 0.0
	recording = true
	# Algrada (esimene rada ei ole kunagi hop)
	last_lane = player.lane
	changes.append({"beat": 0.0, "lane": player.lane, "hop": false})
	music.play()


func song_time() -> float:
	return music.get_playback_position() \
		+ AudioServer.get_time_since_last_mix() \
		- AudioServer.get_output_latency()


## Iga liigutus salvestatakse otse signaalist, nii ei kao kiired jadad kaduma.
func _on_move_started(_from, to, type) -> void:
	if not recording:
		return
	var t := song_time() - reaction - offset
	if type == "tween":
		# Rada vahetub tweeni poolel peal, just seal on chart'i piir
		var dist := absf(lane_x(to) - player.position.x)
		t += 0.5 * dist / scroll_speed
	changes.append({"beat": t * bpm / 60.0, "lane": to, "hop": type == "hop"})
	last_lane = to


func _process(_delta: float) -> void:
	if not recording or not music.playing:
		return
	current_beat = (song_time() - reaction - offset) * bpm / 60.0
	label.text = "Salvestan...  löök %.1f\nEsc = lõpeta ja salvesta" % current_beat


func save_chart() -> void:
	if not recording:
		return
	recording = false

	# Ümarda löögid nii, et kiired jadad ei kuku samale löögile kokku
	var beats: Array = []
	var prev_snapped := -INF
	for c in changes:
		var s := snappedf(c["beat"], snap)
		if prev_snapped >= start_beat and s <= beats[-1]:
			s = beats[-1] + snap
		prev_snapped = snappedf(c["beat"], snap)
		beats.append(maxf(s, start_beat))
	var end_beat := maxf(snappedf(current_beat, snap), beats[-1] + snap)

	var notes: Array = []
	for i in changes.size():
		var b0: float = beats[i]
		var b1: float = beats[i + 1] if i + 1 < changes.size() else end_beat
		if b1 - b0 <= 0.0:
			continue

		var lane: int = changes[i]["lane"]

		if not notes.is_empty():
			var prev: Dictionary = notes[-1]
			if prev["lane"] == lane and is_equal_approx(prev["beat"] + prev["length"], b0):
				prev["length"] += b1 - b0
				continue

		var note := {"beat": b0, "lane": lane, "length": b1 - b0}
		if changes[i].get("hop", false):
			note["hop"] = true
		notes.append(note)

	var lines := PackedStringArray()
	for n in notes:
		var line := '    { "beat": %s, "lane": %d, "length": %s' % [n["beat"], n["lane"], n["length"]]
		if n.get("hop", false):
			line += ', "hop": true'
		line += " }"
		lines.append(line)
	var text := "{\n" \
		+ '  "title": "%s",\n' % song_path.get_file().get_basename() \
		+ '  "audio": "%s",\n' % song_path.get_file() \
		+ '  "bpm": %s,\n' % bpm \
		+ '  "offset": %s,\n' % offset \
		+ '  "notes": [\n' + ",\n".join(lines) + "\n  ]\n}\n"

	# Loome unikaalse failinime ajatempli järgi (nt chart_recorded_20261010_160512.json)
	var dt := Time.get_datetime_dict_from_system()
	var timestamp := "%04d%02d%02d_%02d%02d%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second]
	var dynamic_path = output_path.get_basename() + "_" + timestamp + "." + output_path.get_extension()

	var file := FileAccess.open(dynamic_path, FileAccess.WRITE)
	if file == null:
		label.text = "Salvestamine ebaõnnestus: " + dynamic_path
		return
	file.store_string(text)
	file.close()

	label.text = "Salvestatud %d lõiku:\n%s" % [notes.size(), dynamic_path.get_file()]
	print("Salvestatud: ", ProjectSettings.globalize_path(dynamic_path))
