extends Node2D
## Mängija pall (nõel). Rajade asukohad ja kiiruse küsib game.gd-lt (vanemsõlm),
## nii et pall on alati täpselt rajajoonel ja libiseb mööda 45° diagonaali.
##
## Uus noolevajutus kirjutab käimasoleva liikumise üle: pall alustab uut
## liikumist sealt, kus ta parasjagu on.

signal move_started(from_lane: int, to_lane: int, type: String)   # game.gd hindab selle järgi üleminekuid

const LANES = 4
var lane = 2           # rada hindamise jaoks = pallile lähim rada (alustab keskelt)
var target_lane = 2    # rada, kuhu pall parasjagu liigub
var moving = false     # kas tween käib
var tween: Tween

@onready var game = get_parent()


func _ready():
	position = target_pos(lane)


func _draw():
	draw_circle(Vector2.ZERO, 5, Color.WHITE)


func _process(_delta):
	# Uus vajutus kirjutab käimasoleva liikumise kohe üle
	if Input.is_action_just_pressed("ui_left"):
		start_move(-1)
	elif Input.is_action_just_pressed("ui_right"):
		start_move(1)
	# Nool all hoides jätkab järgmisele rajale, kui eelmine liikumine sai valmis
	elif not moving:
		if Input.is_action_pressed("ui_left"):
			start_move(-1)
		elif Input.is_action_pressed("ui_right"):
			start_move(1)

	# Liikumise ajal on hindamise rada see, millele pall on parasjagu lähemal.
	# Nii vahetub rada täpselt poole liikumise peal, ka siis, kui liikumine katkestati.
	if moving:
		lane = nearest_lane(position.x)


func _unhandled_input(event):
	# Hüpe: kohe teisele rajale, katkestab ka käimasoleva tweeni
	if event.is_action_pressed("hop_left"):
		hop(-1)
	elif event.is_action_pressed("hop_right"):
		hop(1)


func target_pos(l: int) -> Vector2:
	return Vector2(game.lane_x(l), game.hit_line_y)


func nearest_lane(x: float) -> int:
	return clampi(roundi((x - game.lane_x0) / float(game.lane_spacing)), 0, LANES - 1)


func start_move(dir: int):
	# Kui liikumine käib, arvestame selle sihtrajast: samas suunas = edasi,
	# vastassuunas = tagasi sinna, kust tuldi
	var base: int = target_lane if moving else lane
	var new_target := clampi(base + dir, 0, LANES - 1)
	if new_target == base:
		return   # ääres, kuhugi minna pole

	move_started.emit(lane, new_target, "tween")
	if tween:
		tween.kill()
	target_lane = new_target
	moving = true

	# Diagonaal on 45°, ehk pall peab liikuma külgsuunas sama kiiresti kui rada alla.
	# Kestus arvutatakse järelejäänud vahemaa järgi, nii et ka katkestatud
	# liikumine jätkub sama kiirusega.
	var distance := absf(target_pos(target_lane).x - position.x)
	var duration := distance / maxf(game.current_speed(), 1.0)

	tween = create_tween()
	tween.tween_property(self, "position", target_pos(target_lane), duration)
	tween.tween_callback(_on_move_done)


func _on_move_done():
	moving = false
	lane = target_lane
	position = target_pos(lane)


func hop(dir: int):
	var base: int = target_lane if moving else lane
	var new_target := clampi(base + dir, 0, LANES - 1)
	if new_target == base:
		return

	move_started.emit(lane, new_target, "hop")
	if tween:
		tween.kill()
	moving = false
	lane = new_target
	target_lane = new_target
	position = target_pos(lane)
