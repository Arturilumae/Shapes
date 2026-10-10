extends Node2D

const LANES = 4
var lane = 2   # alustab keskmisest rajast
var cd = false

func _ready():
	update_position(0,"hop")

func _draw():
	draw_circle(Vector2.ZERO, 30, Color.WHITE)


func _process(delta):
	if cd:
		return
		
	# Check if keys are held down continuously
	if Input.is_action_pressed("ui_left") and lane > 0:
		update_position(-1,"tween")
	elif Input.is_action_pressed("ui_right") and lane < LANES - 1:
		update_position(1,"tween")


func _unhandled_input(event):
	if cd == true:
		return
	if event.is_action_pressed("ui_left") and lane > 0:
		update_position(-1,"tween")
	if event.is_action_pressed("ui_right") and lane < LANES - 1:
		update_position(1,"tween")
	if event.is_action_pressed("hop_left") and lane > 0:
		update_position(-1,"hop")
	if event.is_action_pressed("hop_right") and lane < LANES - 1:
		update_position(1,"hop")

func update_position(nextlane, type):
	cd = true   # While cd is true, the player is officially "in transit" / off the line
	
	# Calculate target using current lane + nextlane without changing 'lane' yet
	var target_lane = lane + nextlane
	
	var size = get_viewport_rect().size
	var lane_width = size.x / LANES
	var target_position = Vector2(lane_width * (target_lane + 0.5), size.y - 100)
	if type == "tween":
		var tween = create_tween()
		tween.tween_property(self, "position", target_position, 0.5).set_trans(Tween.TRANS_LINEAR)
		tween.finished.connect(movement_finish.bind(nextlane))
	elif type == "hop":
		self.position = target_position
		cd = false
		lane+= nextlane
	
func movement_finish(nextlane):
	lane += nextlane  # Player has officially arrived at the new lane
	cd = false        # Cooldown ends, player is safely on the new line
