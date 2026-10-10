extends Node2D

var speed = 300.0
var length = 80.0

func _ready():
	$ColorRect.size.y = randf_range(length/2, length)
	$ColorRect.position.y = -length

func _process(delta):
	position.y += speed * delta
	# kustuta alles siis, kui ka ülemine ots on ekraanist väljas
	if position.y - length > get_viewport_rect().size.y:
		queue_free()
