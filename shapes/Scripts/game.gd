extends Node2D
## Joonemäng: chart määrab, millal ja millisele rajale joon alla tuleb.
## Kõik jooned ehitatakse ühe pika "Track" sõlme sisse ja liigub ainult Track,
## muusika aja järgi. Mängija peab olema samal rajal, kus joon löögijoonel on.
##
## Pikslikunsti jaoks: kõik asukohad on täisarvud, diagonaalid on 45° ja
## pannakse kokku korduvatest tükkidest (mitte ei venitata).

const LANES := 4
const LINE_COLOR := Color("5dc8ff")
const LINE_HIT_COLOR := Color("7dff8a")
const LINE_HIT_miss := Color("84001dff")

const FRAME := 1.0 / 60.0         # üks mängukaader (60 FPS)
# Diagonaali täpsus vastavalt sellele, mitu kaadrit mööda:
# 0–2 kaadrit -> 100%, 3 -> 80%, 4 -> 60%, 5 -> 40%, 6 -> 20%, edasi 0%
const DIAG_GRADES := [1.0, 1.0, 1.0, 0.8, 0.6, 0.4, 0.2]
const DIAG_EARLY_WINDOW := 0.3    # kui mitu sekundit varem tehtud liigutust veel diagonaaliga seotakse

@export var level_dir := "res://levels/demo/"  # kaust VÕI konkreetne .json fail
@export var scroll_speed := 110.0              # algkiirus px/s (chart'i "speeds" võib muuta)
@export var audio_offset := 0.0                # mängija kalibreering sekundites
@export var fill_gaps := 1.0                   # kuni nii mitme löögi pikkused vahed täidetakse

@export_group("Elud")
@export var max_health := 100.0
@export var health_recover_rate := 15.0        # elu taastub sekundis, kui oled õigel rajal
@export var health_drain_rate := 50.0          # elu kaob sekundis, kui oled valel rajal

@export_group("Paigutus (pikslites)")
@export var play_width := 209                  # mänguala laius (paremal on score ja elud)
@export var lane_x0 := 26                      # esimese raja keskjoone x
@export var lane_spacing := 52                 # kahe raja keskjoonte vahe = diagonaali samm
@export var hit_line_y := 120                  # löögijoone (ja mängija) y
@export var min_straight := 10                 # vähim sirge joon kahe diagonaali vahel

@export_group("Joone spritid")
@export var line_straight: Texture2D           # sirge tükk, nt 3 px lai
@export var line_diag_right: Texture2D         # 45° diagonaal alla paremale ↘ (55×55)
@export var line_diag_left: Texture2D          # 45° diagonaal alla vasakule ↙ (55×55)

@onready var music = $Music          # AudioStreamPlayer või AudioStreamPlayer2D
@onready var track: Node2D = $Track
@onready var player = $Player
@onready var judge_label: Label = $JudgeLabel
@onready var health_bar: ProgressBar = get_node_or_null("HealthBar")

var segments: Array = []   # iga joonelõik: {start, end, lane, rect}
var speed_points: Array = []  # kiiruse muutused: {t, speed, dist}
var current := 0           # esimene lõik, mis pole veel täielikult möödas
var song_time := 0.0
var song_end := 0.0        # viimase lõigu lõpp (kasutatakse, kui laulu pole)
var playing := false
var use_music := false     # kas aeg tuleb laulust või sisemisest kellast
var score := 0.0
var acc_sum := 0.0         # kõigi hinnatud asjade (sirged jooned + diagonaalid) täpsuste summa
var acc_count := 0         # mitu asja on hinnatud
var on_current_line := 0.0
var total_current_line := 0.0
var current_health := 0.0
var transitions: Array = []   # diagonaalid: {t (ideaalne liikumise algus), from, to, done}
var next_trans := 0           # esimene diagonaal, mis pole veel aegunud
var last_diag := ""           # viimase diagonaali tulemus ekraanil


func _ready() -> void:
	var chart_path := level_dir if level_dir.ends_with(".json") else level_dir.path_join("chart.json")
	level_dir = chart_path.get_base_dir()
	var chart := load_chart(chart_path)
	if chart.is_empty():
		return

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
	player.move_started.connect(_on_player_move_started)
	queue_redraw()
	playing = true
	if use_music:
		music.play()


# ---------- Paigutus ----------

func lane_x(lane: int) -> int:
	return lane_x0 + lane_spacing * lane


# ---------- Kiirus ja vahemaa ----------
# dist_at(t) = mitu pikslit on rada ajaks t liikunud.
# Kõik positsioonid tulevad sellest ühest funktsioonist, seega jääb kõik
# muusikaga sünkrooni ka siis, kui kiirus laulu jooksul muutub.

func build_speeds(chart: Dictionary, offset: float, spb: float) -> void:
	speed_points = [{"t": 0.0, "speed": scroll_speed, "dist": 0.0}]
	var list: Array = chart.get("speeds", [])
	list.sort_custom(func(a, b): return a["beat"] < b["beat"])
	for s in list:
		var t := offset + float(s["beat"]) * spb
		var last: Dictionary = speed_points[-1]
		if t <= last["t"]:
			last["speed"] = float(s["speed"])
			continue
		var d: float = last["dist"] + (t - last["t"]) * last["speed"]
		speed_points.append({"t": t, "speed": float(s["speed"]), "dist": d})


func dist_at(t: float) -> float:
	var p: Dictionary = speed_points[0]
	for q in speed_points:
		if q["t"] > t:
			break
		p = q
	return p["dist"] + (t - p["t"]) * p["speed"]


## Raja praegune kiirus px/s (mängija kasutab seda, et libiseda mööda diagonaali).
func current_speed() -> float:
	if speed_points.is_empty():
		return scroll_speed
	var p: Dictionary = speed_points[0]
	for q in speed_points:
		if q["t"] > song_time:
			break
		p = q
	return p["speed"]


## Vastupidine: mis ajal on rada liikunud d pikslit.
func time_at_dist(d: float) -> float:
	var p: Dictionary = speed_points[0]
	for q in speed_points:
		if q["dist"] > d:
			break
		p = q
	return p["t"] + (d - p["dist"]) / p["speed"]


# ---------- Leveli laadimine ----------

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
	build_speeds(chart, offset, spb)

	var notes: Array = chart.get("notes", [])
	notes.sort_custom(func(a, b): return a["beat"] < b["beat"])
	for n in notes:
		var start := offset + float(n["beat"]) * spb
		var end := start + float(n.get("length", 1.0)) * spb
		segments.append({"start": start, "end": end, "lane": int(n["lane"])})
		song_end = maxf(song_end, end)

	# Täida väikesed vahed lõikude vahel, et diagonaalid saaksid tekkida
	for i in range(segments.size() - 1):
		var gap: float = segments[i + 1]["start"] - segments[i]["end"]
		if gap > 0.0 and gap <= fill_gaps * spb + 0.001:
			segments[i]["end"] = segments[i + 1]["start"]

	var count := segments.size()

	# 1) Leia raja vahetused. Diagonaal on 45°: iga raja kohta täpselt
	#    lane_spacing pikslit alla. Selle keskpunkt on raja vahetuse hetkel.
	var trans_mid: Array = []    # diagonaali keskpunkti y (täisarv)
	var trans_half: Array = []   # pool diagonaali kõrgusest (0 = diagonaali pole)
	for i in count:
		trans_mid.append(0)
		trans_half.append(0)
		if i + 1 >= count:
			continue
		var a: Dictionary = segments[i]      # varasem lõik (ekraanil all pool)
		var b: Dictionary = segments[i + 1]  # hilisem lõik (ekraanil ülal pool)
		if a["lane"] == b["lane"] or absf(a["end"] - b["start"]) > 0.001:
			continue
		var jumped: int = absi(b["lane"] - a["lane"])
		trans_mid[i] = roundi(-dist_at(a["end"]))
		trans_half[i] = int(lane_spacing * jumped * 0.5)

	# 2) Kahe järjestikuse diagonaali vahele jääb vähemalt min_straight pikslit
	#    sirget joont. Kui vahetused on liiga lähestikku, lükatakse hilisem edasi
	#    ja selle aeg arvutatakse ümber, et hindamine klapiks sellega, mida näed.
	var shifted := 0
	for i in range(1, count):
		if trans_half[i] == 0 or trans_half[i - 1] == 0:
			continue
		var limit: int = trans_mid[i - 1] - trans_half[i - 1] - min_straight - trans_half[i]
		if trans_mid[i] > limit:
			trans_mid[i] = limit
			var new_t := time_at_dist(-limit)
			segments[i]["end"] = new_t
			segments[i + 1]["start"] = new_t
			segments[i + 1]["end"] = maxf(segments[i + 1]["end"], new_t)
			shifted += 1

	# 3) Diagonaalide sõlmed
	for i in count:
		if trans_half[i] == 0:
			continue
		var a: Dictionary = segments[i]
		var b: Dictionary = segments[i + 1]
		var piece := DiagPiece.new()
		piece.down_right = b["lane"] < a["lane"]   # hilisem rada vasakul => alla paremale
		piece.tex = line_diag_right if piece.down_right else line_diag_left
		piece.jumped = absi(b["lane"] - a["lane"])
		piece.step = lane_spacing
		piece.color = LINE_COLOR
		# Diagonaali nullpunkt on selle ülemine ots (hilisema raja keskjoon)
		piece.position = Vector2(lane_x(b["lane"]), trans_mid[i] - trans_half[i])
		track.add_child(piece)

	# 4) Sirged tükid diagonaalide vahele
	var too_short := 0
	for i in count:
		var seg: Dictionary = segments[i]
		var top := roundi(-dist_at(seg["end"]))
		var bottom := roundi(-dist_at(seg["start"]))
		if trans_half[i] > 0:
			top = trans_mid[i] + trans_half[i]           # järgmise diagonaali alumine ots
		if i > 0 and trans_half[i - 1] > 0:
			bottom = trans_mid[i - 1] - trans_half[i - 1]  # eelmise diagonaali ülemine ots
		if bottom < top:
			too_short += 1

		var piece := StraightPiece.new()
		piece.tex = line_straight
		piece.color = LINE_COLOR
		piece.height = maxi(0, bottom - top)
		piece.position = Vector2(lane_x(seg["lane"]), top)
		track.add_child(piece)
		seg["rect"] = piece
		# Hitbox = täpselt sirge tüki ulatus. Diagonaali ajal ei hinnata midagi.
		# (bottom on ekraanil all = varasem aeg, top on ülal = hilisem aeg)
		seg["hit_start"] = time_at_dist(-bottom)
		seg["hit_end"] = time_at_dist(-top)

	# 5) Diagonaalide hindamine: ideaalne hetk liikumise alustamiseks on see,
	#    kui sirge joon löögijoonel lõpeb (diagonaali alumine ots jõuab sinna).
	for i in count:
		if trans_half[i] == 0:
			continue
		transitions.append({
			"t": segments[i]["hit_end"],
			"from": segments[i]["lane"],
			"to": segments[i + 1]["lane"],
			"done": false,
		})

	if shifted > 0:
		push_warning("%d raja vahetust nihutati edasi, sest need olid liiga lähestikku. Suurem kiirus (Scroll Speed või chart'i \"speeds\") hoiab need muusikaga täpsemalt koos." % shifted)
	if too_short > 0:
		push_warning("%d lõiku on diagonaalide jaoks liiga lühikesed." % too_short)


# ---------- Ajastus ----------

func update_song_time(delta: float) -> void:
	if use_music:
		# Laulu korral võetakse aeg otse helimängijast, siis ei teki triivi
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

	# Rada liigub tervete pikslite kaupa, siis ei lähe midagi taustaga nihkesse
	track.position.y = roundi(hit_line_y + dist_at(t))

	# Jäta vahele lõigud, mis on juba mööda läinud
	while current < segments.size() and segments[current]["hit_end"] <= t:
		current += 1
		if total_current_line > 0.0:
			acc_sum += on_current_line / total_current_line
			acc_count += 1
		on_current_line = 0
		total_current_line = 0

	# Diagonaalid, mille ajal mängija ei liikunud õigel ajal: 0%
	while next_trans < transitions.size() and t > transitions[next_trans]["t"] + 6 * FRAME:
		var tr: Dictionary = transitions[next_trans]
		if not tr["done"]:
			tr["done"] = true
			acc_count += 1
			last_diag = "Diagonaal: 0%"
		next_trans += 1

	# Kas mõni sirge joon on praegu löögijoonel? (diagonaali ajal on vahe, siis ei hinnata)
	if current < segments.size() and segments[current]["hit_start"] <= t:
		var seg: Dictionary = segments[current]
		total_current_line += delta

		if player.lane == seg["lane"]:
			on_current_line += delta
			score += 100.0 * delta
			current_health = minf(current_health + health_recover_rate * delta, max_health)
			show_status("Joonel!")
		else:
			current_health -= health_drain_rate * delta
			show_status("Mööda!")
			if current_health <= 0.0:
				current_health = 0.0
				game_over()

		if health_bar:
			health_bar.value = current_health

		# Joon muutub punasest roheliseks vastavalt sellele, kui suure osa ajast olid joonel
		var ratio := on_current_line / total_current_line
		seg["rect"].modulate = LINE_HIT_miss.lerp(LINE_HIT_COLOR, ratio)


func show_status(text: String) -> void:
	var accuracy := 0.0
	if acc_count > 0:
		accuracy = acc_sum / acc_count * 100.0
	judge_label.text = "%s\nskoor %d   täpsus %d%%\n%s" % [text, int(score), int(accuracy), last_diag]


## Mängija alustas liikumist teisele rajale (player.gd saadab selle signaali).
## Leiame lähima hindamata diagonaali samas suunas ja hindame ajastust kaadrites.
func _on_player_move_started(from_lane: int, to_lane: int, type: String) -> void:
	if not playing:
		return
	var t := song_time
	var dir := signi(to_lane - from_lane)
	for i in range(next_trans, transitions.size()):
		var tr: Dictionary = transitions[i]
		if tr["done"]:
			continue
		if tr["t"] - t > DIAG_EARLY_WINDOW:
			break   # järgmine diagonaal on veel liiga kaugel, see liigutus ei ole selle jaoks
		if signi(tr["to"] - tr["from"]) != dir:
			continue  # vale suund
		tr["done"] = true
		acc_count += 1
		# Hüpe (Q/E) jätab diagonaali vahele: täpsus 0%
		if type == "hop":
			last_diag = "Diagonaal: 0% (hüpe)"
			return
		var frames := roundi(absf(t - tr["t"]) / FRAME)
		var grade: float = DIAG_GRADES[frames] if frames < DIAG_GRADES.size() else 0.0
		acc_sum += grade
		score += 100.0 * grade
		last_diag = "Diagonaal: %d%%" % int(grade * 100)
		return


func _on_song_finished() -> void:
	playing = false
	show_status("Lõpp!")


func game_over() -> void:
	playing = false
	if use_music:
		music.stop()
	judge_label.text = "MÄNG LÄBI!\nElud said otsa."
	# Uuesti alustamiseks: get_tree().reload_current_scene()


# ---------- Radade ja löögijoone joonistamine ----------

func _draw() -> void:
	var h := get_viewport_rect().size.y
	for lane in LANES:
		var x := lane_x(lane) + 0.5
		draw_line(Vector2(x, 0), Vector2(x, h), Color(1, 1, 1, 0.15), 1.0)
	draw_line(Vector2(0, hit_line_y + 0.5), Vector2(play_width, hit_line_y + 0.5), Color(1, 1, 1, 0.4), 1.0)


# ---------- Joone tükid ----------

## Sirge tükk. Sprite korratakse ülevalt alla ühise ruudustiku järgi,
## nii et muster jätkub katkematult üle kõigi tükkide.
class StraightPiece extends Node2D:
	var tex: Texture2D
	var color := Color.WHITE
	var height := 0

	func _draw() -> void:
		if tex == null:
			draw_rect(Rect2(-1, 0, 3, height), color)
			return
		var tw := tex.get_width()
		var th := tex.get_height()
		var x := -floori(tw / 2.0)
		var y := -posmod(int(position.y), th)
		while y < height:
			var top := maxi(y, 0)
			var bottom := mini(y + th, height)
			if bottom > top:
				draw_texture_rect_region(tex, Rect2(x, top, tw, bottom - top),
					Rect2(0, top - y, tw, bottom - top))
			y += th


## 45° diagonaal. Nullpunkt on ülemine ots (hilisema raja keskjoon).
## Iga hüpatud raja kohta joonistatakse üks sprite, midagi ei venitata.
class DiagPiece extends Node2D:
	var tex: Texture2D
	var color := Color.WHITE
	var down_right := true
	var jumped := 1
	var step := 52

	func _draw() -> void:
		var dir := 1 if down_right else -1
		if tex == null:
			draw_line(Vector2.ZERO, Vector2(dir * step * jumped, step * jumped), color, 3.0)
			return
		# Raam = kui palju on sprite suurem kui 1 px joone tuum (55 - 53) / 2 = 1
		var border := floori((tex.get_width() - (step + 1)) / 2.0)
		for k in jumped:
			var x := step * k if down_right else -step * (k + 1)
			draw_texture(tex, Vector2(x - border, step * k - border))
