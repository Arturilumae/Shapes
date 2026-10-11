extends Node2D
## Mängija pall (nõel). Rajade asukohad ja kiiruse küsib game.gd-lt (vanemsõlm),
## nii et pall on alati täpselt rajajoonel ja libiseb mööda 45° diagonaali.
##
## Uus noolevajutus kirjutab käimasoleva liikumise üle: pall alustab uut
## liikumist sealt, kus ta parasjagu on.
## Hüpe (Q/E) on sama libisemine, aga palju kiirem.

signal move_started(from_lane: int, to_lane: int, type: String)   # game.gd hindab selle järgi üleminekuid
signal lane_changed(new_lane: int, type: String)                  # salvestaja kasutab: hindamise rada vahetus

@export var hop_speed := 5000.0        # hüppe kiirus px/s (1500 => üks rada ~0,035 s ehk ~2 kaadrit)
@export var anim_per_lane := 1.0       # mitu korda push/pull animatsioon ühe raja läbimise ajal läbi mängib

const LANES = 4
var lane = 2           # rada hindamise jaoks = pallile lähim rada (alustab keskelt)
var target_lane = 2    # rada, kuhu pall parasjagu liigub
var moving = false     # kas tween käib
var tween: Tween

@onready var game = get_parent()
@onready var noel: AnimatedSprite2D = $kalle
@onready var movesound: AudioStreamPlayer = $MoveSound

func _ready():
	position = target_pos(lane)


func _process(_delta):
	# Nool all hoides jätkab järgmisele rajale, kui eelmine liikumine sai valmis
	# (uued vajutused tulevad _unhandled_input kaudu)
	if not moving:
		if Input.is_action_pressed("ui_left"):
			start_move(-1)
		elif Input.is_action_pressed("ui_right"):
			start_move(1)

	# Liikumise ajal on hindamise rada see, millele pall on parasjagu lähemal.
	# Nii vahetub rada täpselt poole liikumise peal, ka siis, kui liikumine katkestati.
	if moving:
		set_lane(nearest_lane(position.x), "tween")


func _unhandled_input(event):
	# Iga vajutus loetakse eraldi sündmusena, nii et ka kaks vajutust
	# samas kaadris lähevad kirja. Uus vajutus kirjutab käimasoleva liikumise üle.
	if event.is_action_pressed("ui_left"):
		start_move(-1)
	elif event.is_action_pressed("ui_right"):
		start_move(1)
	# Hüpe: kiire libisemine teisele rajale
	elif event.is_action_pressed("hop_left"):
		movesound.play()
		hop(-1)
	elif event.is_action_pressed("hop_right"):
		movesound.play()
		hop(1)


func target_pos(l: int) -> Vector2:
	return Vector2(game.lane_x(l), game.hit_line_y)

func snap_to_lane(l: int) -> void: # Used in tutorial
	if tween:
		tween.kill()
	moving = false
	target_lane = l
	position = target_pos(l)
	set_lane(l, "tween")
	noel.speed_scale = 1.0
	noel.play("idle")

func nearest_lane(x: float) -> int:
	return clampi(roundi((x - game.lane_x0) / float(game.lane_spacing)), 0, LANES - 1)


## Hindamise raja muutmine; annab märku ainult siis, kui rada tegelikult vahetus.
func set_lane(new_lane: int, type: String):
	if new_lane == lane:
		return
	lane = new_lane
	lane_changed.emit(new_lane, type)


func start_move(dir: int):
	# Kui liikumine käib, arvestame selle sihtrajast: samas suunas = edasi,
	# vastassuunas = tagasi sinna, kust tuldi
	var base: int = target_lane if moving else lane
	var new_target := clampi(base + dir, 0, LANES - 1)
	if new_target == base:
		return   # ääres, kuhugi minna pole

	move_started.emit(lane, new_target, "tween")
	# Diagonaal on 45°, ehk pall peab liikuma külgsuunas sama kiiresti kui rada alla
	slide_to(new_target, game.current_speed())


func hop(dir: int):
	if moving:
		return   # hüpe ei katkesta käimasolevat liikumist
	var new_target := clampi(lane + dir, 0, LANES - 1)
	if new_target == lane:
		return   # ääres

	move_started.emit(lane, new_target, "hop")
	# Sama libisemine nagu diagonaalil, aga hop_speed kiirusega
	slide_to(new_target, hop_speed)


## Animatsiooni pikkus sekundites (kõigi kaadrite kestus kokku FPS järgi).
func anim_length(anim: String) -> float:
	var frames := noel.sprite_frames
	if frames == null or not frames.has_animation(anim):
		return 0.0
	var total := 0.0
	for i in frames.get_frame_count(anim):
		total += frames.get_frame_duration(anim, i)
	return total / maxf(frames.get_animation_speed(anim), 0.001)


## Libista pall rajale `target` kiirusega `speed` (px/s).
## Kestus arvutatakse järelejäänud vahemaa järgi, nii et ka katkestatud
## liikumine jätkub sama kiirusega.
func slide_to(target: int, speed: float):
	if tween:
		tween.kill()
	target_lane = target
	moving = true

	var heading := signf(target_pos(target_lane).x - position.x)
	var anim := "push" if heading > 0 else "pull"

	# Animatsiooni kiirus liikumise kiiruse järgi: ühe raja läbimise ajal
	# mängib animatsioon anim_per_lane korda läbi (hüppel seega väga kiiresti)
	var lane_time: float = game.lane_spacing / maxf(speed, 1.0)
	var length := anim_length(anim)
	noel.speed_scale = length / lane_time * anim_per_lane if length > 0.0 else 1.0
	# Kui sama animatsioon juba mängib (nool all hoides), jätkub see katkematult
	if noel.animation != anim or not noel.is_playing():
		noel.play(anim)

	var distance := absf(target_pos(target_lane).x - position.x)
	var duration := distance / maxf(speed, 1.0)

	tween = create_tween()
	tween.tween_property(self, "position", target_pos(target_lane), duration)
	tween.tween_callback(_on_move_done)


func _on_move_done():
	moving = false
	position = target_pos(target_lane)
	set_lane(target_lane, "tween")

	# Nool on endiselt all: jätka kohe järgmisele rajale, ilma vahepealse idle'ita
	if Input.is_action_pressed("ui_left") and lane > 0:
		start_move(-1)
		return
	if Input.is_action_pressed("ui_right") and lane < LANES - 1:
		start_move(1)
		return

	noel.speed_scale = 1.0
	noel.play("idle")
