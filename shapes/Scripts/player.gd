extends Node2D

const LANES = 4
var lane = 2   # alustab keskmisest rajast

func _ready():
	update_position()

func _draw():
	draw_circle(Vector2.ZERO, 30, Color.WHITE)

func _unhandled_input(event):
	if event.is_action_pressed("ui_left") and lane > 0:
		lane -= 1
		update_position()
	if event.is_action_pressed("ui_right") and lane < LANES - 1:
		lane += 1
		update_position()

func update_position():
	var size = get_viewport_rect().size
	var lane_width = size.x / LANES
	position = Vector2(lane_width * (lane + 0.5), size.y - 100)
