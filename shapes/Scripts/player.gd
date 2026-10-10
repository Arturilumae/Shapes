extends Node2D
## Mängija pall. Rajade asukohad ja kiiruse küsib game.gd-lt (vanemsõlm),
## nii et pall on alati täpselt rajajoonel ja libiseb mööda 45° diagonaali.

const LANES = 4
var lane = 2      # rada, mille järgi mängu hinnatakse (alustab keskelt)
var cd = false    # true = pall liigub parasjagu radade vahel

@onready var game = get_parent()


func _ready():
	position = target_pos(lane)


func _draw():
	draw_circle(Vector2.ZERO, 5, Color.WHITE)


func _process(_delta):
	if cd:
		return
	# Nooleklahv all hoides liigub pall sujuvalt rajalt rajale
	if Input.is_action_pressed("ui_left") and lane > 0:
		move(-1, "tween")
	elif Input.is_action_pressed("ui_right") and lane < LANES - 1:
		move(1, "tween")


func _unhandled_input(event):
	if cd:
		return
	# Hüpe: kohe teisele rajale
	if event.is_action_pressed("hop_left") and lane > 0:
		move(-1, "hop")
	elif event.is_action_pressed("hop_right") and lane < LANES - 1:
		move(1, "hop")


func target_pos(l: int) -> Vector2:
	return Vector2(game.lane_x(l), game.hit_line_y)


func move(dir: int, type: String):
	var target_lane: int = lane + dir

	if type == "hop":
		lane = target_lane
		position = target_pos(lane)
		return

	cd = true
	# Diagonaal on 45°, ehk ühe raja jagu üle sõitmiseks kulub
	# lane_spacing / kiirus sekundit. Sama ajaga liigub pall külgsuunas,
	# nii et see libiseb täpselt mööda diagonaali.
	var duration: float = game.lane_spacing / maxf(game.current_speed(), 1.0)

	var tween := create_tween()
	tween.tween_property(self, "position", target_pos(target_lane), duration)
	# Rada vahetub hindamise jaoks poole liikumise peal, täpselt nagu diagonaali keskel
	tween.parallel().tween_callback(func(): lane = target_lane).set_delay(duration / 2.0)
	tween.tween_callback(func(): cd = false)
