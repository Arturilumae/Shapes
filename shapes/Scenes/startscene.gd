extends Node2D

@export var next_scene := "res://Scenes/LevelSelect.tscn"

# Adjust this path if your AnimatedSprite2D has a different name
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	# Connect to the animation_finished signal of AnimatedSprite2D
	animated_sprite.animation_finished.connect(_on_animation_finished)
	
	# Optional: If your animation doesn't auto-play, start it here:
	# animated_sprite.play("your_animation_name")


func _process(delta: float) -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo():
		_finish()


func _on_animation_finished() -> void:
	_finish()


func _finish() -> void:
	set_process(false)
	get_tree().change_scene_to_file(next_scene)
