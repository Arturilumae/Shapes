extends Node2D
## Mängija pall (nõel). Rajade asukohad ja kiiruse küsib game.gd-lt (vanemsõlm),
## nii et pall on alati täpselt rajajoonel ja libiseb mööda 45° diagonaali.
##
## Uus noolevajutus kirjutab käimasoleva liikumise üle: pall alustab uut
## liikumist sealt, kus ta parasjagu on.

signal move_started(from_lane: int, to_lane: int, type: String)   # game.gd hindab selle järgi üleminekuid
signal lane_changed(new_lane: int, type: String)                  # salvestaja kasutab: hindamise rada vahetus

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
	# Hüpe: kohe teisele rajale, katkestab ka käimasoleva tweeni
	elif event.is_action_pressed("hop_left"):
		hop(-1)
	elif event.is_action_pressed("hop_right"):
		hop(1)


func target_pos(l: int) -> Vector2:
	return Vector2(game.lane_x(l), game.hit_line_y)


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
	position = target_pos(target_lane)
	set_lane(target_lane, "tween")


func hop(dir: int):
	if moving == true:
		return
	var new_target: int
	if moving:
		# Hüpe käimasoleva liikumise ajal ei lisa vahemaad juurde:
		# samas suunas = lõpeta liikumine hüppega (maandub sihtrajale),
		# vastassuunas = hüppa ühe raja võrra pallile lähimast rajast
		var heading := signf(target_pos(target_lane).x - position.x)
		if signf(dir) == heading:
			new_target = target_lane
		else:
			new_target = clampi(lane + dir, 0, LANES - 1)
	else:
		new_target = clampi(lane + dir, 0, LANES - 1)
	if new_target == lane:
		return   # ääres, või pall on juba sihtrajal (hindamise rada on juba vahetunud)

	move_started.emit(lane, new_target, "hop")
	if tween:
		tween.kill()
	moving = false
	target_lane = new_target
	position = target_pos(new_target)
	set_lane(new_target, "hop")
