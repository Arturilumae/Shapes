extends Node2D

@export var line_scene: PackedScene
const LANES = 4
const MAX_JUMP = 2
const SPEED_UP = 20.0
var last_lane = 2
var line_speed = 300.0
const SEGMENT_LENGTH = 150.0

func _process(delta):
	line_speed += SPEED_UP * delta
	$Timer.wait_time = SEGMENT_LENGTH / line_speed

func _on_timer_timeout():
	var line = line_scene.instantiate()

	var r = randf()
	var jump
	if r < 0.25:
		jump = 0          # 1/4 – jääb samasse rajasse
	elif r < 0.25 + 0.125:
		jump = 2          # 1/8 – hüppab 2 rada
	else:
		jump = 1  # ülejäänud 5/8 – hüppab 1 raja

	var dir = 1 if randf() < 0.5 else -1
	var lane = last_lane + jump * dir
	if lane < 0 or lane > LANES - 1:
		lane = last_lane - jump * dir
	last_lane = lane

	var lane_width = get_viewport_rect().size.x / LANES
	line.position = Vector2(lane_width * (lane + 0.5), -50)
	line.speed = line_speed
	line.length = SEGMENT_LENGTH + 2
	add_child(line)
	print(line_speed)
