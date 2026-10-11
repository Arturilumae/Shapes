extends Node2D
## Tiitrid kerivad alt üles. Mis tahes klahv või tiitrite lõpp viib tagasi.

@export var scroll_speed := 20.0                      # px sekundis
@export var next_scene := "res://Scenes/MainMenu.tscn"      # kuhu pärast minna (või main.tscn)

@onready var label: Label = $CreditsLabel
var y := 0.0


func _ready() -> void:
	y = get_viewport_rect().size.y   # alusta ekraani alt


func _process(delta: float) -> void:
	y -= scroll_speed * delta
	label.position.y = roundi(y)     # terved pikslid, siis tekst ei värise
	# Kui viimane rida on ekraanist üles läinud, on tiitrid läbi
	if y + label.size.y < 0:
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo():
		_finish()


func _finish() -> void:
	set_process(false)
	get_tree().change_scene_to_file(next_scene)
