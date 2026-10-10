extends Node2D
## Joonemäng: chart määrab, millal ja millisele rajale joon alla tuleb.
## Kõik jooned ehitatakse ühe pika "Track" sõlme sisse ja liigub ainult Track,
## muusika aja järgi. Mängija peab olema samal rajal, kus joon löögijoonel on.

const LANES := 4
const LINE_WIDTH := 30.0
const LINE_COLOR := Color("5dc8ff")
const LINE_HIT_COLOR := Color("7dff8a")
const LINE_HIT_miss := Color("84001dff")

@export var level_dir := "res://levels/demo/"  # või nt "user://levels/minu_lugu"
@export var scroll_speed := 300.0              # pikslit sekundis
@export var audio_offset := 0.0                # mängija kalibreering sekundites

# --- Uued elude (health) muutujad ---
@export var max_health := 100.0
@export var health_recover_rate := 15.0        # Mitu elu punkti taastub sekundis, kui oled õigel rajal
@export var health_drain_rate := 50.0          # Mitu elu punkti kaotad sekundis, kui oled valel rajal

@onready var music = $Music          # AudioStreamPlayer või AudioStreamPlayer2D
@onready var track: Node2D = $Track
@onready var player = $Player
@onready var judge_label: Label = $JudgeLabel
@onready var health_bar: ProgressBar = $HealthBar # Lisa stseeni ProgressBar node nimega "HealthBar"

var segments: Array = []   # iga joonelõik: {start, end, lane, rect}
var current := 0           # esimene lõik, mis pole veel täielikult möödas
var song_time := 0.0
var song_end := 0.0        # viimase lõigu lõpp (kasutatakse, kui laulu pole)
var playing := false
var use_music := false     # kas aeg tuleb laulust või sisemisest kellast
var score := 0.0
var total_line_time := 0.0
var on_current_line := 0.0
var total_current_line := 0.0

var current_health := 0.0  # Mängija hetke elud


func _ready() -> void:
	var chart := load_chart(level_dir.path_join("chart.json"))
	if chart.is_empty():
		return

	# Seadistame elud
	current_health = max_health
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = current_health

	# Laul on valikuline: kui seda pole, töötab level sisemise kella järgi
	var audio_name: String = chart.get("audio", "")
	var stream: AudioStream = null
	if audio_name != "":
		stream = load_audio(level_dir.path_join(audio_name))
	if stream != null:
		music.stream = stream
		music.finished.connect(_on_song_finished)
		use_music = true
	else:
		push_warning("Laulu pole, kasutan sisemist kella.")

	build_track(chart)
	queue_redraw()
	playing = true
	if use_music:
		music.play()


# ---------- Abifunktsioonid, mis klapivad player.gd-ga ----------

func hit_y() -> float:
	return get_viewport_rect().size.y - 100.0   # sama y, kus mängija ring on

func lane_x(lane: int) -> float:
	return get_viewport_rect().size.x / LANES * (lane + 0.5)


# ---------- Leveli laadimine ----------
# (Sama, mis enne)
func load_chart(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Ei leia leveli faili: " + path)
		return {}
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Vigane JSON: " + path)
		return {}
	return data

func load_audio(path: String) -> AudioStream:
	if path.begins_with("res://"):
		if not ResourceLoader.exists(path):
			return null
		return load(path)
	if not FileAccess.file_exists(path):
		return null
	match path.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			var stream := AudioStreamMP3.new()
			stream.data = FileAccess.get_file_as_bytes(path)
			return stream
	return null


# ---------- Pika liikuva raja ehitamine ----------
func build_track(chart: Dictionary) -> void:
	var bpm: float = chart.get("bpm", 120.0)
	var offset: float = chart.get("offset", 0.0)
	var spb := 60.0 / bpm   # sekundeid ühe löögi kohta
	var notes: Array = chart.get("notes", [])
	notes.sort_custom(func(a, b): return a["beat"] < b["beat"])

	for n in notes:
		var lane := int(n["lane"])
		var start := offset + float(n["beat"]) * spb
		var end := start + float(n.get("length", 1.0)) * spb

		var rect := ColorRect.new()
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.color = LINE_COLOR
		rect.size = Vector2(LINE_WIDTH, (end - start) * scroll_speed)
		rect.position = Vector2(lane_x(lane) - LINE_WIDTH / 2, -end * scroll_speed)
		track.add_child(rect)

		segments.append({"start": start, "end": end, "lane": lane, "rect": rect})
		song_end = maxf(song_end, end)


# ---------- Ajastus ----------
func update_song_time(delta: float) -> void:
	if use_music:
		if music.playing:
			song_time = music.get_playback_position() \
				+ AudioServer.get_time_since_last_mix() \
				- AudioServer.get_output_latency() \
				+ audio_offset
	else:
		song_time += delta
		if song_time > song_end + 1.0:
			_on_song_finished()


# ---------- Mängu loogika ----------
func _process(delta: float) -> void:
	if not playing:
		return
	update_song_time(delta)
	var t := song_time

	# Kogu rada liigub muusika aja järgi
	track.position.y = hit_y() + t * scroll_speed

	# Jäta vahele lõigud, mis on juba mööda läinud
	while current < segments.size() and segments[current]["end"] <= t:
		current += 1
		if total_current_line > 0:
			total_line_time += on_current_line / total_current_line
		on_current_line = 0
		total_current_line = 0

	# Kas mõni lõik on praegu löögijoonel?
	if current < segments.size() and segments[current]["start"] <= t:
		var seg: Dictionary = segments[current]
		total_current_line += delta
		
		if player.lane == seg["lane"]:
			# Mängija on õigel rajal (HIT)
			on_current_line += delta
			score += 100.0 * delta
			seg["rect"].color = (LINE_HIT_COLOR - LINE_HIT_miss) * (on_current_line / total_current_line) + LINE_HIT_miss
			show_status("Joonel!")
			
			# Taastame elusid ja hoiame neid max_health piires
			current_health = minf(current_health + health_recover_rate * delta, max_health)
			
		else:
			# Mängija on valel rajal (MISS)
			seg["rect"].color = (LINE_HIT_COLOR - LINE_HIT_miss) * (on_current_line / total_current_line) + LINE_HIT_miss
			show_status("Mööda!")
			
			# Kaotame elusid
			current_health -= health_drain_rate * delta
			
			# Kontrollime, kas elud said otsa
			if current_health <= 0.0:
				current_health = 0.0
				game_over()
		
		# Uuendame UI eluderiba
		if health_bar:
			health_bar.value = current_health


func show_status(text: String) -> void:
	var accuracy := 0.0
	if current > 0:
		accuracy = total_line_time / current * 100.0
	judge_label.text = "%s\nskoor %d   täpsus %d%%" % [text, int(score), int(accuracy)]


func _on_song_finished() -> void:
	playing = false
	show_status("Lõpp!")

func game_over() -> void:
	playing = false
	if use_music:
		music.stop()
	judge_label.text = "MÄNG LÄBI!\nElud said otsa."
	# Siia võid lisada loogika stseeni uuesti laadimiseks
	# nt. get_tree().reload_current_scene()


# ---------- Radade ja löögijoone joonistamine ----------
func _draw() -> void:
	var height := get_viewport_rect().size.y
	for lane in LANES:
		var x := lane_x(lane)
		draw_line(Vector2(x, 0), Vector2(x, height), Color(1, 1, 1, 0.15), 2)
	draw_line(Vector2(0, hit_y()), Vector2(get_viewport_rect().size.x, hit_y()), Color(1, 1, 1, 0.4), 2)
