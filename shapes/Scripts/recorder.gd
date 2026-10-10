extends Node2D
## Salvestusrežiim: laul mängib, sina liigud ringiga radade vahel,
## ja iga raja vahetus salvestatakse chart'iks samas formaadis, mida game.gd loeb.
##
## Tühik = alusta, Esc = lõpeta ja salvesta (salvestab ka laulu lõppedes ise).

@export var song_path := "res://levels/demo/song.ogg"
@export var bpm := 120.0          # laulu BPM (nt Pythoni skripti väljundist)
@export var offset := 0.0         # esimese löögi aeg sekundites
@export var snap := 0.5           # mitme löögi täpsusega ümardatakse (1, 0.5, 0.25)
@export var start_beat := 4.0     # varasemad liigutused jäetakse välja
@export var reaction := 0.05      # sinu reaktsiooniaeg sekundites, lahutatakse maha
@export var output_path := "res://levels/demo/chart_recorded.json"

@onready var music: AudioStreamPlayer = $Music
@onready var player = $Player
@onready var label: Label = $Label

var changes: Array = []   # iga raja vahetus: {beat, lane}
var last_lane := -1
var current_beat := 0.0
var recording := false


func _ready() -> void:
	music.stream = load(song_path)
	if music.stream == null:
		label.text = "Laulu ei leitud: " + song_path
		return
	music.finished.connect(save_chart)
	label.text = "Tühik = alusta salvestamist"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not recording and music.stream != null:
		start()
	elif event.is_action_pressed("ui_cancel") and recording:
		music.stop()
		save_chart()


func start() -> void:
	changes.clear()
	last_lane = -1
	current_beat = 0.0
	recording = true
	music.play()


func song_time() -> float:
	return music.get_playback_position() \
		+ AudioServer.get_time_since_last_mix() \
		- AudioServer.get_output_latency()


func _process(_delta: float) -> void:
	if not recording or not music.playing:
		return
	current_beat = (song_time() - reaction - offset) * bpm / 60.0

	if player.lane != last_lane:
		changes.append({"beat": current_beat, "lane": player.lane})
		last_lane = player.lane

	label.text = "Salvestan...  löök %.1f\nEsc = lõpeta ja salvesta" % current_beat


func save_chart() -> void:
	if not recording:
		return
	recording = false

	var notes: Array = []
	for i in changes.size():
		var b0 := maxf(snappedf(changes[i]["beat"], snap), start_beat)
		var b1: float
		if i + 1 < changes.size():
			b1 = snappedf(changes[i + 1]["beat"], snap)
		else:
			b1 = snappedf(current_beat, snap)
		if b1 - b0 <= 0.0:
			continue
		var lane: int = changes[i]["lane"]
		if not notes.is_empty():
			var prev: Dictionary = notes[-1]
			if prev["lane"] == lane and is_equal_approx(prev["beat"] + prev["length"], b0):
				prev["length"] += b1 - b0
				continue
		notes.append({"beat": b0, "lane": lane, "length": b1 - b0})

	var lines := PackedStringArray()
	for n in notes:
		lines.append('    { "beat": %s, "lane": %d, "length": %s }' % [n["beat"], n["lane"], n["length"]])
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
