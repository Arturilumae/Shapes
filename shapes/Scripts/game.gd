extends Node2D
## Joonemäng: chart määrab, millal ja millisele rajale joon alla tuleb.
## Kõik jooned ehitatakse ühe pika "Track" sõlme sisse ja liigub ainult Track,
## muusika aja järgi. Mängija peab olema samal rajal, kus joon löögijoonel on.
##
## Joon koosneb sirgetest tükkidest (raja peal) ja diagonaalidest (raja vahetusel).
## Kui sprite'e pole määratud, joonistatakse lihtsad värvilised jooned.

const LANES := 4
const LINE_WIDTH := 30.0
const LINE_COLOR := Color("5dc8ff")
const LINE_HIT_COLOR := Color("7dff8a")
const LINE_HIT_miss := Color("84001dff")

@export var level_dir := "res://levels/demo/"  # kaust VÕI konkreetne .json fail
@export var scroll_speed := 300.0              # pikslit sekundis
@export var audio_offset := 0.0                # mängija kalibreering sekundites

# --- Uued elude (health) muutujad ---
@export var max_health := 100.0
@export var health_recover_rate := 15.0        # Mitu elu punkti taastub sekundis, kui oled õigel rajal
@export var health_drain_rate := 50.0          # Mitu elu punkti kaotad sekundis, kui oled valel rajal


@export_group("Joone spritid")
@export var line_straight: Texture2D    # sirge tükk (joon läheb otse alla)
@export var line_diag_right: Texture2D  # diagonaal, mis läheb alla paremale ↘
@export var line_diag_left: Texture2D   # diagonaal, mis läheb alla vasakule ↙
@export var line_scale := 1.0           # sprite'ide suurendus
@export var diag_height := 0.0          # diagonaali kõrgus pikslites (0 = pildi kuju järgi)

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
	var chart_path := level_dir if level_dir.ends_with(".json") else level_dir.path_join("chart.json")
	level_dir = chart_path.get_base_dir()
	var chart := load_chart(chart_path)
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


func line_width() -> float:
	if line_straight:
		return line_straight.get_width() * line_scale
	return LINE_WIDTH


func diag_height_for(lanes_jumped: int, tex: Texture2D) -> float:
	if diag_height > 0.0:
		return diag_height * lanes_jumped
	var lane_dx := get_viewport_rect().size.x / LANES
	var box_w := lanes_jumped * lane_dx + line_width()
	if tex:
		# Säilitame diagonaalpildi kuju (kõrguse ja laiuse suhte)
		return box_w * tex.get_height() / tex.get_width()
	return lanes_jumped * lane_dx * 0.5


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

	var w := line_width()

	# 1) Diagonaalid: kus kaks lõiku järgnevad vahetult ja rada muutub.
	#    diag[i] = diagonaali kõrgus lõigu i ja i+1 vahel (0 = diagonaali pole).
	var diag: Array = []
	for i in segments.size():
		diag.append(0.0)
		if i + 1 >= segments.size():
			continue
		var a: Dictionary = segments[i]      # varasem lõik (ekraanil all pool)
		var b: Dictionary = segments[i + 1]  # hilisem lõik (ekraanil ülal pool)
		if a["lane"] == b["lane"] or absf(a["end"] - b["start"]) > 0.001:
			continue

		# Ülevalt alla vaadates: kui hilisem lõik on vasakul, läheb joon alla paremale
		var down_right: bool = b["lane"] < a["lane"]
		var tex: Texture2D = line_diag_right if down_right else line_diag_left
		var jumped: int = absi(b["lane"] - a["lane"])
		var d := diag_height_for(jumped, tex)
		# Diagonaal ei tohi olla pikem kui kumbki naaberlõik
		var len_a: float = (a["end"] - a["start"]) * scroll_speed
		var len_b: float = (b["end"] - b["start"]) * scroll_speed
		d = minf(d, minf(len_a, len_b))
		diag[i] = d

		var xa := lane_x(a["lane"])
		var xb := lane_x(b["lane"])
		var y_mid: float = -a["end"] * scroll_speed   # raja vahetuse hetk
		var piece := DiagPiece.new()
		piece.tex = tex
		piece.color = LINE_COLOR
		piece.line_w = w
		piece.box = Vector2(absf(xb - xa) + w, d)
		piece.bottom_left = xa < xb
		piece.position = Vector2(minf(xa, xb) - w / 2, y_mid - d / 2)
		track.add_child(piece)

	# 2) Sirged tükid. Kus diagonaal algab või lõpeb, jääb sirge tükk poole võrra lühemaks.
	for i in segments.size():
		var seg: Dictionary = segments[i]
		var y_top: float = -seg["end"] * scroll_speed
		var y_bottom: float = -seg["start"] * scroll_speed
		if i > 0:
			y_bottom -= diag[i - 1] / 2
		y_top += diag[i] / 2

		var piece := StraightPiece.new()
		piece.tex = line_straight
		piece.color = LINE_COLOR
		piece.line_w = w
		piece.line_scale = line_scale
		piece.height = maxf(0.0, y_bottom - y_top)
		piece.position = Vector2(lane_x(seg["lane"]), y_top)
		track.add_child(piece)
		seg["rect"] = piece


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

		# Kaitse nulliga jagamise eest: lõik võis mööduda ühe kaadri vahel
		if total_current_line > 0.0:
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
			show_status("Joonel!")
			
			# Taastame elusid ja hoiame neid max_health piires
			current_health = minf(current_health + health_recover_rate * delta, max_health)
			
		else:
			# Mängija on valel rajal (MISS)
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
			show_status("Mööda!")
			
		# Joon muutub punasest roheliseks vastavalt sellele, kui suure osa ajast olid joonel
		if seg["rect"] != null:
			var ratio := on_current_line / total_current_line
			seg["rect"].modulate = LINE_HIT_miss.lerp(LINE_HIT_COLOR, ratio)
		# Joon muutub punasest roheliseks vastavalt sellele, kui suure osa ajast olid joonel
		var ratio := on_current_line / total_current_line
		seg["rect"].modulate = (LINE_HIT_COLOR - LINE_HIT_miss) * ratio + LINE_HIT_miss


func show_status(text: String) -> void:
	var accuracy := 0.0
	if total_line_time > 0.0 and current > 0:
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


# ---------- Joone tükid ----------

## Sirge tükk. Sprite korratakse ülevalt alla, et see sobiks iga pikkusega.
class StraightPiece extends Node2D:
	var tex: Texture2D
	var color := Color.WHITE
	var line_w := 30.0
	var line_scale := 1.0
	var height := 0.0

	func _draw() -> void:
		if tex == null:
			draw_rect(Rect2(-line_w / 2, 0, line_w, height), color)
			return
		var tw := tex.get_width() * line_scale
		var th := tex.get_height() * line_scale
		var y := 0.0
		while y < height - 0.01:
			var h := minf(th, height - y)
			draw_texture_rect_region(tex, Rect2(-tw / 2, y, tw, h),
				Rect2(0, 0, tex.get_width(), h / line_scale))
			y += th


## Diagonaaltükk raja vahetuse kohal. Sprite venitatakse kasti suuruseks.
class DiagPiece extends Node2D:
	var tex: Texture2D
	var color := Color.WHITE
	var line_w := 30.0
	var box := Vector2.ZERO
	var bottom_left := false   # kas alumine ots (varasem rada) on vasakul

	func _draw() -> void:
		if tex:
			draw_texture_rect(tex, Rect2(Vector2.ZERO, box), false)
			return
		var half := line_w / 2
		var top_x := box.x - half if bottom_left else half
		var bottom_x := half if bottom_left else box.x - half
		draw_line(Vector2(top_x, 0), Vector2(bottom_x, box.y), color, line_w)
