extends TextureButton


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_pressed_play() -> void:
	get_tree().change_scene_to_file("res://Scenes/startscene.tscn")

func _on_pressed_settings() -> void:
	get_tree().change_scene_to_file("res://Scenes/LevelSelect.tscn")
	
func _on_pressed_credits() -> void:
	get_tree().change_scene_to_file("res://Scenes/credits.tscn")
	
func _on_pressed_back() -> void:
	get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")
	
func _on_pressed_lvl0() -> void:
	get_tree().change_scene_to_file("res://Scenes/level_0.tscn")
func _on_pressed_lvl1() -> void:
	get_tree().change_scene_to_file("res://Scenes/level_1.tscn")
func _on_pressed_lvl2() -> void:
	get_tree().change_scene_to_file("res://Scenes/level_2.tscn")
func _on_pressed_lvl3() -> void:
	get_tree().change_scene_to_file("res://Scenes/level_3.tscn")
