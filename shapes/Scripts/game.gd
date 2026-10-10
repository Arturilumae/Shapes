extends Node2D
## Joonemäng: chart määrab, millal ja millisele rajale joon alla tuleb.
## Kõik jooned ehitatakse ühe pika "Track" sõlme sisse ja liigub ainult Track,
## muusika aja järgi. Mängija peab olema samal rajal, kus joon löögijoonel on.
##
## Pikslikunsti jaoks: kõik asukohad on täisarvud, diagonaalid on 45° ja
## pannakse kokku korduvatest tükkidest (mitte ei venitata).
##
## Hindamine:
##   - sirged jooned: skoor ja täpsus raja järgi (mitu % ajast olid õigel rajal)
##   - diagonaalid ja hüpped: täpsus liikumise alustamise ajastuse järgi (kaadrites)
##   - elud: nõela hitbox-ringi kaugus joone keskjoonest (pikslites)


#region Konstandid

const LANES := 4
const LINE_HIT_COLOR := Color("7f95b1")
const LINE_MISS_COLOR := Color("492045")

const FRAME := 1.0 / 60.0         # üks mängukaader (60 FPS)
# Ülemineku täpsus vastavalt sellele, mitu kaadrit mööda:
# 0–2 kaadrit -> 100%, 3 -> 80%, 4 -> 60%, 5 -> 40%, 6 -> 20%, edasi 0%
const DIAG_GRADES := [1.0, 1.0, 1.0, 0.8, 0.6, 0.4, 0.2]
const DIAG_EARLY_WINDOW := 0.3    # kui mitu sekundit varem tehtud liigutust veel üleminekuga seotakse

#endregion


#region Seaded (Inspector)

@export var level_dir := "res://levels/demo/tuljak_chart.json"  # kaust VÕI konkreetne .json fail
@export var scroll_speed := 110.0              # algkiirus px/s (chart'i "speeds" võib muuta)
@export var audio_offset := 0.0                # mängija kalibreering sekundites
@export var fill_gaps := 1.0                   # kuni nii mitme löögi pikkused vahed täidetakse

@export_group("Elud")
@export var max_health := 100.0
@export var health_recover_rate := 7.0         # elu taastub sekundis, kui nõel on joonel
@export var health_drain_rate := 70.0          # suurim elu kadu sekundis (kui nõel on drain_full_px kaugusel)
@export var hitbox_radius := 1.0               # nõela ringi raadius px: 0 = täpselt joone keskmisel pikslil, 1 = 3 px joone sees
@export var drain_full_px := 15                # mitme px kaugusel ringi servast kaob elu täiskiirusel

@export_group("Paigutus (pikslites)")
@export var play_width := 209                  # mänguala laius (paremal on score ja elud)
@export var lane_x0 := 26                      # esimese raja keskjoone x
@export var lane_spacing := 52                 # kahe raja keskjoonte vahe = diagonaali samm
@export var hit_line_y := 104                  # löögijoone (ja mängija) y
@export var min_straight := 10                 # vähim sirge joon kahe ülemineku vahel

@export_group("Joone spritid")
@export var line_straight: Texture2D           # sirge tükk, nt 3 px lai
@export var line_diag_right: Texture2D         # 45° diagonaal alla paremale ↘ (55×55)
@export var line_diag_left: Texture2D          # 45° diagonaal alla vasakule ↙ (55×55)
@export var line_left: Texture2D               # järsk tükk vasakule (53×3)
@export var line_right: Texture2D              # järsk tükk paremale (53×3)

@export_group("Debug")
@export var debug_hitbox := false              # näita nõela hitbox-ringi

#endregion


#region Sõlmed

@onready var music = $Music          # AudioStreamPlayer või AudioStreamPlayer2D
@onready var track: Node2D = $Track
@onready var player = $Player
@onready var judge_label: Label = get_node_or_null("JudgeLabel")
@onready var health_bar: Range = get_node_or_null("%HealthBar")
@onready var score_label: Label = get_node_or_null("%ScoreLabel")
@onready var accuracy_label: Label = get_node_or_null("%AccuracyLabel")

#endregion


#region Olek

# Rada
var segments: Array = []      # iga sirge lõik: {start, end, lane, hop, rect, hit_start, hit_end, trans_in}
var transitions: Array = []   # üleminekud: {t (ideaalne liikumise algus), from, to, kind, node, done}
var speed_points: Array = []  # kiiruse muutused: {t, speed, dist}
var geo: Array = []           # joone keskjoon lõikudena raja koordinaatides: {a, b, ymin, ymax}

# Ajastus
var song_time := 0.0
var song_end := 0.0           # viimase lõigu lõpp (kasutatakse, kui laulu pole)
var playing := false
var use_music := false        # kas aeg tuleb laulust või sisemisest kellast

# Edenemine rajal (indeksid, mis liiguvad ainult edasi)
var current := 0              # esimene sirge lõik, mis pole veel täielikult möödas
var next_trans := 0           # esimene üleminek, mis pole veel aegunud
var geo_idx := 0              # esimene geo-lõik, mis pole veel täielikult möödas

# Hindamine
var score := 0.0
var acc_sum := 0.0            # kõigi hinnatud asjade (sirged + üleminekud) täpsuste summa
var acc_count := 0            # mitu asja on hinnatud
var on_current_line := 0.0    # praegusel sirgel joonel õigel rajal veedetud aeg
var total_current_line := 0.0 # praeguse sirge joone hinnatud aeg kokku
var last_diag := ""           # viimase ülemineku tulemus ekraanil

# Elud
var current_health := 0.0
var last_dist := INF          # viimati mõõdetud kaugus nõelast joone keskjooneni (debug jaoks)

#endregion


#region Elutsükkel

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

	_setup_music(chart)
	build_track(chart)
	player.move_started.connect(_on_player_move_started)
	queue_redraw()

	if debug_hitbox:
		var overlay := DebugOverlay.new()
		overlay.game = self
		overlay.z_index = 100   # kõige peal
		add_child(overlay)

	playing = true
	if use_music:
		music.play()


func _process(delta: float) -> void:
	if not playing:
		return
	update_song_time(delta)
	var t := song_time

	# Rada liigub tervete pikslite kaupa, siis ei lähe midagi taustaga nihkesse
	track.position.y = roundi(hit_line_y + dist_at(t))

	_advance_segments(t)
	_expire_transitions(t)
	_judge_straight_line(delta, t)
	update_health(delta, t)
	_update_hud()


## Rajajooned ja löögijoon (abijooned).


#endregion


#region Leveli ja muusika laadimine

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


## Laul on valikuline: kui seda pole, töötab level sisemise kella järgi.
func _setup_music(chart: Dictionary) -> void:
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

#endregion


#region Aeg, kiirus ja vahemaa
# dist_at(t) = mitu pikslit on rada ajaks t liikunud.
# Kõik positsioonid tulevad sellest ühest funktsioonist, seega jääb kõik
# muusikaga sünkrooni ka siis, kui kiirus laulu jooksul muutub.

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


## Vastupidine: mis ajal on rada liikunud d pikslit.
func time_at_dist(d: float) -> float:
	var p: Dictionary = speed_points[0]
	for q in speed_points:
		if q["dist"] > d:
			break
		p = q
	return p["t"] + (d - p["dist"]) / p["speed"]


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


## Raja keskjoone x.
func lane_x(lane: int) -> int:
	return lane_x0 + lane_spacing * lane

#endregion


#region Raja ehitamine

func build_track(chart: Dictionary) -> void:
	var bpm: float = chart.get("bpm", 120.0)
	var offset: float = chart.get("offset", 0.0)
	var spb := 60.0 / bpm   # sekundeid ühe löögi kohta

	build_speeds(chart, offset, spb)
	_read_segments(chart, offset, spb)
	_fill_gaps(spb)

	var links := _find_transitions()
	var shifted := _space_transitions(links)
	_spawn_transition_pieces(links)
	var too_short := _spawn_straight_pieces(links)
	_register_transitions(links)

	# Geo-lõigud järjekorda: alumised (varasemad) enne
	geo.sort_custom(func(p, q): return p["ymax"] > q["ymax"])

	if shifted > 0:
		push_warning("%d raja vahetust nihutati edasi, sest need olid liiga lähestikku. Suurem kiirus (Scroll Speed või chart'i \"speeds\") hoiab need muusikaga täpsemalt koos." % shifted)
	if too_short > 0:
		push_warning("%d lõiku on üleminekute jaoks liiga lühikesed." % too_short)


## Chart'i noodid -> sirged lõigud (aeg sekundites).
func _read_segments(chart: Dictionary, offset: float, spb: float) -> void:
	var notes: Array = chart.get("notes", [])
	notes.sort_custom(func(a, b): return a["beat"] < b["beat"])
	for n in notes:
		var start := offset + float(n["beat"]) * spb
		var end := start + float(n.get("length", 1.0)) * spb
		# "hop": true tähendab, et sellele lõigule hüpatakse järsu horisontaalse tükiga
		segments.append({"start": start, "end": end, "lane": int(n["lane"]),
			"hop": bool(n.get("hop", false))})
		song_end = maxf(song_end, end)


## Täida väikesed vahed lõikude vahel, et üleminekud saaksid tekkida.
func _fill_gaps(spb: float) -> void:
	for i in range(segments.size() - 1):
		var gap: float = segments[i + 1]["start"] - segments[i]["end"]
		if gap > 0.0 and gap <= fill_gaps * spb + 0.001:
			segments[i]["end"] = segments[i + 1]["start"]


## Leia raja vahetused. links[i] kirjeldab üleminekut lõigult i lõigule i+1:
##   kind: "" (pole), "diag" (45° diagonaal) või "hop" (järsk horisontaalne tükk)
##   mid:  ülemineku keskpunkti y raja koordinaatides
##   half: pool ülemineku kõrgusest (hop puhul 0)
##   node: ülemineku sõlm (täidetakse hiljem, värvimiseks pärast hindamist)
func _find_transitions() -> Array:
	var links: Array = []
	for i in segments.size():
		var link := {"kind": "", "mid": 0, "half": 0, "node": null}
		links.append(link)
		if i + 1 >= segments.size():
			continue
		var a: Dictionary = segments[i]      # varasem lõik (ekraanil all pool)
		var b: Dictionary = segments[i + 1]  # hilisem lõik (ekraanil ülal pool)
		if a["lane"] == b["lane"] or absf(a["end"] - b["start"]) > 0.001:
			continue
		var jumped: int = absi(b["lane"] - a["lane"])
		link["mid"] = roundi(-dist_at(a["end"]))
		if b["hop"]:
			link["kind"] = "hop"
		else:
			link["kind"] = "diag"
			link["half"] = int(lane_spacing * jumped * 0.5)
	return links


## Kahe järjestikuse ülemineku vahele jääb vähemalt min_straight pikslit sirget
## joont. Kui üleminekud on liiga lähestikku, lükatakse hilisem edasi ja selle
## aeg arvutatakse ümber, et hindamine klapiks sellega, mida näed.
## Tagastab nihutatud üleminekute arvu.
func _space_transitions(links: Array) -> int:
	var shifted := 0
	for i in range(1, links.size()):
		var prev: Dictionary = links[i - 1]
		var link: Dictionary = links[i]
		if link["kind"] == "" or prev["kind"] == "":
			continue
		var limit: int = prev["mid"] - prev["half"] - min_straight - link["half"]
		if link["mid"] > limit:
			link["mid"] = limit
			var new_t := time_at_dist(-limit)
			segments[i]["end"] = new_t
			segments[i + 1]["start"] = new_t
			segments[i + 1]["end"] = maxf(segments[i + 1]["end"], new_t)
			shifted += 1
	return shifted


## Diagonaalide ja hüppetükkide sõlmed + nende keskjoon elude arvutamiseks.
func _spawn_transition_pieces(links: Array) -> void:
	for i in links.size():
		var link: Dictionary = links[i]
		if link["kind"] == "":
			continue
		var xa := lane_x(segments[i]["lane"])       # varasem rada
		var xb := lane_x(segments[i + 1]["lane"])   # hilisem rada
		var jumped: int = absi(segments[i + 1]["lane"] - segments[i]["lane"])
		var mid: int = link["mid"]
		var half: int = link["half"]

		if link["kind"] == "hop":
			var hop := HopPiece.new()
			hop.to_left = xb < xa
			hop.tex = line_left if hop.to_left else line_right
			hop.jumped = jumped
			hop.step = lane_spacing
			# Nullpunkt on vasakpoolsema raja keskjoon, raja vahetuse kõrgusel
			hop.position = Vector2(mini(xa, xb), mid)
			hop.z_index = 1   # sirgete joonte peale, et ääred jääksid õigeks
			track.add_child(hop)
			link["node"] = hop
			add_geo(Vector2(xa, mid), Vector2(xb, mid))
		else:
			var diag := DiagPiece.new()
			diag.down_right = xb < xa   # hilisem rada vasakul => alla paremale
			diag.tex = line_diag_right if diag.down_right else line_diag_left
			diag.jumped = jumped
			diag.step = lane_spacing
			# Nullpunkt on ülemine ots (hilisema raja keskjoon)
			diag.position = Vector2(xb, mid - half)
			track.add_child(diag)
			link["node"] = diag
			add_geo(Vector2(xb, mid - half), Vector2(xa, mid + half))


## Sirged tükid üleminekute vahele. Iga sirge tüki ulatus on ka selle hitbox.
## Tagastab nende lõikude arvu, millele sirget tükki ei jäänud.
func _spawn_straight_pieces(links: Array) -> int:
	var too_short := 0
	for i in segments.size():
		var seg: Dictionary = segments[i]
		var x := lane_x(seg["lane"])
		var top := roundi(-dist_at(seg["end"]))
		var bottom := roundi(-dist_at(seg["start"]))
		if links[i]["kind"] != "":
			top = links[i]["mid"] + links[i]["half"]               # järgmise ülemineku alumine ots
		if i > 0 and links[i - 1]["kind"] != "":
			bottom = links[i - 1]["mid"] - links[i - 1]["half"]    # eelmise ülemineku ülemine ots
		if bottom < top:
			too_short += 1

		var piece := StraightPiece.new()
		piece.tex = line_straight
		piece.height = maxi(0, bottom - top)
		piece.position = Vector2(x, top)
		track.add_child(piece)
		if bottom > top:
			add_geo(Vector2(x, top), Vector2(x, bottom))

		seg["rect"] = piece
		# Hitbox ajas (bottom on ekraanil all = varasem aeg, top on ülal = hilisem aeg)
		seg["hit_start"] = time_at_dist(-bottom)
		seg["hit_end"] = time_at_dist(-top)
		# Mis üleminek viib sellele lõigule ("", "diag" või "hop")
		seg["trans_in"] = links[i - 1]["kind"] if i > 0 else ""
	return too_short


## Üleminekute hindamise andmed. Ideaalne hetk liikumise alustamiseks on see,
## kui sirge joon löögijoonel lõpeb.
func _register_transitions(links: Array) -> void:
	for i in links.size():
		var link: Dictionary = links[i]
		if link["kind"] == "":
			continue
		transitions.append({
			"t": segments[i]["hit_end"],
			"from": segments[i]["lane"],
			"to": segments[i + 1]["lane"],
			"kind": link["kind"],
			"node": link["node"],
			"done": false,
		})

#endregion


#region Hindamine: sirged jooned ja üleminekud

## Lõpeta sirged jooned, mis on löögijoonest mööda läinud, ja lisa nende hinne.
func _advance_segments(t: float) -> void:
	while current < segments.size() and segments[current]["hit_end"] <= t:
		current += 1
		if total_current_line > 0.0:
			acc_sum += on_current_line / total_current_line
			acc_count += 1
		on_current_line = 0.0
		total_current_line = 0.0


## Üleminekud, mille ajal mängija ei liikunud õigel ajal: 0%.
func _expire_transitions(t: float) -> void:
	var late_window := (DIAG_GRADES.size() - 1) * FRAME
	while next_trans < transitions.size() and t > transitions[next_trans]["t"] + late_window:
		var tr: Dictionary = transitions[next_trans]
		if not tr["done"]:
			tr["done"] = true
			acc_count += 1
			grade_transition(tr, 0.0)
			last_diag = "%s: 0%%" % _transition_label(tr)
		next_trans += 1


## Sirge joon löögijoonel: skoor, täpsus ja värv raja järgi.
## (Ülemineku ajal on sirgete joonte vahel tühimik, siis ei hinnata.)
func _judge_straight_line(delta: float, t: float) -> void:
	if current >= segments.size() or segments[current]["hit_start"] > t:
		return
	var seg: Dictionary = segments[current]
	total_current_line += delta
	if player.lane == seg["lane"]:
		on_current_line += delta
		score += 100.0 * delta
	_update_judge_label()

	# Joon muutub punasest roheliseks vastavalt sellele, kui suure osa ajast olid joonel
	var ratio := on_current_line / total_current_line
	seg["rect"].modulate = LINE_MISS_COLOR.lerp(LINE_HIT_COLOR, ratio)


## Mängija alustas liikumist teisele rajale (player.gd saadab selle signaali).
## Leiame lähima hindamata ülemineku samas suunas ja hindame ajastust kaadrites.
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
			break   # järgmine üleminek on veel liiga kaugel
		if signi(tr["to"] - tr["from"]) != dir:
			continue  # vale suund
		tr["done"] = true
		acc_count += 1

		# Diagonaal tuleb läbida tweeniga (nooled), järsk tükk hüppega (Q/E).
		var needed := "tween" if tr["kind"] == "diag" else "hop"
		if type != needed:
			grade_transition(tr, 0.0)
			last_diag = "%s: 0%% (vale liikumine)" % _transition_label(tr)
			return

		var frames := roundi(absf(t - tr["t"]) / FRAME)
		var grade: float = DIAG_GRADES[frames] if frames < DIAG_GRADES.size() else 0.0
		grade_transition(tr, grade)
		acc_sum += grade
		score += 100.0 * grade
		last_diag = "%s: %d%%" % [_transition_label(tr), int(grade * 100)]
		return


## Üleminek sai hinde (0..1): värvi see hinde järgi.
func grade_transition(tr: Dictionary, grade: float) -> void:
	var node: Node2D = tr["node"]
	if node:
		node.modulate = LINE_MISS_COLOR.lerp(LINE_HIT_COLOR, grade)


func _transition_label(tr: Dictionary) -> String:
	return "Diagonaal" if tr["kind"] == "diag" else "Hüpe"


func accuracy_percent() -> float:
	return acc_sum / acc_count * 100.0 if acc_count > 0 else 0.0

#endregion


#region Elud: nõela hitbox-ring

## Kus on joone keskpunkt löögijoonel ajal t (x pikslites)?
## Tagastab NAN, kui löögijoonel pole praegu joont (enne algust, pausis või lõpus).
func line_x_at(t: float) -> float:
	if current >= segments.size():
		return NAN
	var seg: Dictionary = segments[current]
	if seg["hit_start"] <= t:
		return lane_x(seg["lane"])   # sirge joon (ka kohe pärast hüpet)
	if current > 0 and seg["trans_in"] == "diag":
		var prev: Dictionary = segments[current - 1]
		if t >= prev["hit_end"]:
			# Diagonaal on 45°: joone x liigub sama palju, kui rada alla liigub
			var d0 := dist_at(prev["hit_end"])
			var d1 := dist_at(seg["hit_start"])
			var f := clampf((dist_at(t) - d0) / maxf(d1 - d0, 1.0), 0.0, 1.0)
			return lerpf(lane_x(prev["lane"]), lane_x(seg["lane"]), f)
	return NAN


## Lisa joone keskjoone lõik (raja koordinaatides) elude arvutamiseks.
func add_geo(a: Vector2, b: Vector2) -> void:
	geo.append({"a": a, "b": b, "ymin": minf(a.y, b.y), "ymax": maxf(a.y, b.y)})


## Lühim kaugus punktist c (raja koordinaatides) joone keskjooneni.
## Vaadatakse ainult lõike, mis on c-le vertikaalselt piisavalt lähedal.
func distance_to_line(c: Vector2) -> float:
	var margin := hitbox_radius + drain_full_px
	# Rada liigub üles, nii et täielikult allapoole jäänud lõike pole enam vaja
	while geo_idx < geo.size() and geo[geo_idx]["ymin"] > c.y + margin:
		geo_idx += 1
	var best := INF
	for i in range(geo_idx, geo.size()):
		var s: Dictionary = geo[i]
		if s["ymax"] < c.y - margin:
			break   # see ja kõik järgmised on ringist kõrgemal
		var p := Geometry2D.get_closest_point_to_segment(c, s["a"], s["b"])
		best = minf(best, c.distance_to(p))
	return best


## Ring (raadius hitbox_radius) on nõela otsas. Kui joone keskjoon on ringi sees,
## taastuvad elud. Kui ei ole, kaovad elud seda kiiremini, mida kaugemal joon
## ringi servast on, ja drain_full_px kaugusel täiskiirusel.
func update_health(delta: float, t: float) -> void:
	if is_nan(line_x_at(t)):
		last_dist = INF
		return   # löögijoonel pole joont, elud ei muutu

	# Nõela 1 px ots raja koordinaatides (rada liigub ainult y suunas).
	# Ümardatud täispikslini, sama ruudustik mis joone keskmisel pikslil.
	var c: Vector2 = player.position.round() - track.position
	var d := distance_to_line(c)
	last_dist = d

	if d <= hitbox_radius:
		current_health = minf(current_health + health_recover_rate * delta, max_health)
	else:
		var k := clampf((d - hitbox_radius) / float(drain_full_px), 0.0, 1.0)
		current_health -= health_drain_rate * k * delta
		if current_health <= 0.0:
			current_health = 0.0
			game_over()

#endregion


#region UI ja mängu lõpp

func _update_hud() -> void:
	if health_bar:
		health_bar.value = current_health
	if score_label:
		score_label.text = "%06d" % int(score)
	if accuracy_label:
		# Enne esimest hinnatud joont näita 100%
		var acc := accuracy_percent() if acc_count > 0 else 100.0
		accuracy_label.text = "%d%%" % int(acc)


func _update_judge_label() -> void:
	if judge_label and acc_count > 0:
		judge_label.text = "täpsus %d%%\n%s" % [int(accuracy_percent()), last_diag]


func _on_song_finished() -> void:
	playing = false
	_update_judge_label()


func game_over() -> void:
	playing = false
	if use_music:
		music.stop()
	if judge_label:
		judge_label.text = "MÄNG LÄBI!\nElud said otsa."
	# Uuesti alustamiseks: get_tree().reload_current_scene()

#endregion


#region Joone tükid ja debug-vaade

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


## Järsk horisontaalne tükk raja vahetuse kohal (hüppe jaoks).
## Nullpunkt on vasakpoolsema raja keskjoon. Iga hüpatud raja kohta üks sprite.
class HopPiece extends Node2D:
	var tex: Texture2D
	var color := Color.WHITE
	var to_left := false
	var jumped := 1
	var step := 52

	func _draw() -> void:
		if tex == null:
			draw_rect(Rect2(0, -1, step * jumped + 1, 3), color)
			return
		# Raam: sprite 53×3 = 1 px tuum (step + 1 lai) + 1 px üles ja alla
		var border_x := floori((tex.get_width() - (step + 1)) / 2.0)
		var border_y := floori((tex.get_height() - 1) / 2.0)
		for k in jumped:
			draw_texture(tex, Vector2(step * k - border_x, -border_y))


## Debug-vaade: nõela hitbox pikslitena.
##   Roheline = joone keskjoon on ringi sees (elud taastuvad)
##   Punane   = väljas (elud kaovad)
class DebugOverlay extends Node2D:
	var game

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var g = game
		var p: Vector2 = g.player.position.round()
		var inside: bool = g.last_dist <= g.hitbox_radius
		var col := Color(0, 1, 0, 0.6) if inside else Color(1, 0.3, 0.3, 0.6)
		# Iga piksel, mille keskpunkt on nõelast hitbox_radius kaugusel või lähemal
		var r: float = g.hitbox_radius
		var n := ceili(r)
		for dy in range(-n, n + 1):
			for dx in range(-n, n + 1):
				if Vector2(dx, dy).length() <= r:
					draw_rect(Rect2(p + Vector2(dx, dy), Vector2.ONE), col)

#endregion
