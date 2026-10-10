extends GridContainer

func _ready() -> void:
	for child in get_children():
		if child is Button:
			child.pressed.connect(_load_level.bind(child.text))

func _load_level(level_name: String) -> void:
	get_tree().change_scene_to_file("res://Scenes/level_%s.tscn" % level_name)
