extends CharacterBody3D


# https://www.youtube.com/watch?v=M3VnsRIPlck
# https://www.youtube.com/watch?v=v3zT3Z5apaM
# https://github.com/axel37/godot-quake-movement/blob/main/Player.gd

@export var look_sens := Vector2(0.001, 0.001)
@export var auto_jump    := false # auto bhop.

@export var wishspeed       : float =   4.0 # metres per second.
@export var wishcrouchspeed : float =   1.5
@export var wishairspeed    : float =   2.0
@export var wishslidespeed  : float =   0.02 # control speed while sliding
@export var fastairspeed    : float =   0.02 # control speed in air when going fast
@export var accel           : float =  80.0 # or max_speed * 10 = 1/10th of a second.
@export var frict           : float =   7.0 # higher = less slippy - in quake-based games, usually 1-5.
@export var max_ramp_angle  : float =  45.0 : set = _set_max_ramp_angle # max angle player can go up at full speed.
@export var min_slide_angle : float =  25.0 # min angle player would slide on ramps
@export var max_slide_speed : float =  14.0 # max speed 
@export var fastspeed       : float =   5.5 # how fast is fast, dictates behaviour like fastairspeed

@export var grav         : float = ProjectSettings.get_setting("physics/3d/default_gravity")
@export var jump_impulse : float = 4.5

@export var sprint_multiplier : float =  1.5
@export var crouch_speed      : float =  6.0
@export var stand_height      : float =  1.74 # height while standing.
@export var crouch_height     : float =  0.85 # height while crouching.

@export var mega_jump_multiplier : float = 1.8  # jump height multiplied after crouching.
@export var mega_jump_window     : float = 0.45 # window after crouching for a mega jump.
@export var mega_jump_max_charge : float = 0.5

@export var head_crouch_height : float = 0.56
@export var head_stand_height  : float = 1.35

@export var slidefrict   : float =  -1.0
@export var slidespeed   : float =  5.0

@export var slopesnap    : float =  1.0
@export var coyote_time  : float =  0.35
@export var slipspeed    : float = 11.5
@export var slipspeedmax : float = 16.0
@export var slipfrict    : float =  1.0

@onready var head      := $Head
@onready var camera    := $Head/Camera
@onready var collision := $Collision
@onready var leadbonk  := $LeadingBonkRay # area where player would stand. used to check collision before uncrouching.
@onready var bonk      := $BonkRay
@onready var floorray  := $FloorDistance

# accessibility
@export var toggle_crouch    := false
@export var toggle_sprint    := false
@export var always_mega_jump := false

var player_control := true

var terminal_vel : float = grav * -5 # when reached, stop increasing fall speed.

var movedir  := Vector2.ZERO
var wishdir  := Vector3.ZERO
var next_vel := Vector3.ZERO

var vertical_vel        : float = 0.0
var current_speed       : float = 0.0
var add_speed           : float = 0.0
var total_vel           : float = 0.0
var floor_distance      : float = -1

var sprinting       := false # is player sprinting?
var crouching       := false # is player crouching?
var force_crouch    := false # is player forced to crouch? are they in an area where they can't stand up?
var sliding         := false # is player sliding?
var wish_jump       := false # is player jump queued? jump key can be held before hitting the ground.

var coyote_timer     := coyote_time
var mega_jump_timer  := mega_jump_window
var mega_jump_charge : float = 0.0

var head_default_position := Vector3.ZERO
var head_crouch_offset    : float = 0.0





func _ready() -> void:
	head_default_position = head.position



func _process(_delta) -> void:
	floor_distance = snappedf(floorray.get_collision_point().distance_to(floorray.global_position) + 0.001, 0.01)
	#print(floor_distance)



func _physics_process(delta) -> void:
	total_vel = velocity.length()
	#print(total_vel)
	
	
	if player_control:
		movedir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward").normalized()
	else:
		movedir = Vector2.ZERO
	
	# wishdir is our normalized horizontal input.
	wishdir = Vector3(movedir.x, 0, movedir.y).rotated(Vector3.UP, self.global_transform.basis.get_euler().y).normalized()
	
	
	leadbonk.position.y = collision.shape.height
	
	leadbonk.target_position.y = stand_height - collision.shape.height
	leadbonk.target_position.x = velocity.x / 2
	leadbonk.target_position.z = velocity.z / 2
	
	bonk.position.y = leadbonk.position.y
	bonk.target_position.y = leadbonk.target_position.y
	
	leadbonk.rotation.y = -rotation.y # cancelling out player rotation.
	
	
	if player_control:
		queue_jump()
		handle_sprint()
		handle_crouch()
	
	
	# crouching.
	if crouching or force_crouch:
		# adjust collision shape and position, head position.
		collision.shape.height = lerp(collision.shape.height, crouch_height, crouch_speed * delta)
		collision.position.y = collision.shape.height / 2
		head.position.y = lerp(head.position.y, head_crouch_height, crouch_speed * delta)
	else:
		# adjust collision shape and position, head position.
		if collision.shape.height > stand_height - 0.01: # round up when adequate.
			collision.shape.height = stand_height
		else:
			collision.shape.height = lerp(collision.shape.height, stand_height, crouch_speed * delta)
		collision.position.y = collision.shape.height / 2
		head.position.y = lerp(head.position.y, head_stand_height, crouch_speed * delta)
	
	
	# movement.
	if is_on_floor():
		coyote_timer = coyote_time
		
		if wish_jump: # if we're on the ground, but this is true, we've just landed.
			floor_snap_length = 0.0
			jump(delta)
		
		else:
			floor_snap_length = slopesnap
			move_ground(velocity, delta)
	
	else: # air time 😎, no friction.
		floor_snap_length = slopesnap if velocity.length() < slipspeed else 0
		# stop adding to vertical vel once terminal vel has been reached.
		vertical_vel -= grav * delta if vertical_vel >= terminal_vel else 0
		# Subtract time from coyote time.
		if coyote_timer > 0:
			coyote_timer -= delta
			
			# coyote time jump.
			if wish_jump:
				jump(delta)
		
		move_air(velocity, delta)
	
	if is_on_ceiling():
		vertical_vel = 0
	
	
	# deplete mega jump timer.
	if mega_jump_timer > 0:
		mega_jump_timer -= delta
	
	# mega jump charge won't go down unless the window is up.
	elif mega_jump_charge > 0:
		mega_jump_charge = max(0, mega_jump_charge - delta)
	
	if crouching:
		# only allow mega jump.
		if is_on_floor():
			# reset mega jump timer.
			mega_jump_timer = mega_jump_window
		
			# charge mega jump.
			mega_jump_charge = min(mega_jump_max_charge, mega_jump_charge + delta)
	
	
	$Mesh.mesh.height = collision.shape.height
	$Mesh.position.y  = collision.position.y
	
	collision.shape.height = clamp(collision.shape.height, crouch_height, stand_height)
	
	if Input.is_action_just_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	# Camera rotation.
	if event is InputEventMouseMotion and player_control:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			rotate_y(-event.relative.x * look_sens.x)
			head.rotate_x(-event.relative.y * look_sens.y)
			
			head.rotation.x = clamp(head.rotation.x, -PI/2, PI/2)
	elif event is InputEventMouseButton and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	pass





func accelerate(wishdir: Vector3, input_vel: Vector3, accel: float, max_speed: float, delta: float) -> Vector3:
	current_speed = input_vel.dot(wishdir)
	
	add_speed = clamp(max_speed - current_speed, 0, accel * delta)
	
	return input_vel + add_speed * wishdir

func friction(input_vel: Vector3, delta: float) -> Vector3:
	var speed := input_vel.length()
	var scaled_vel : Vector3
	
	if speed != 0:
		var newfrict : float = frict
		
		sliding = false
		
		if crouching:
			if velocity.length() >= slidespeed:
				newfrict = slidefrict
				sliding = true
		
		elif min(max(speed - slipspeed, 0), slipspeedmax - slipspeed) / (slipspeedmax - slipspeed) > 0:
			newfrict = slipfrict
		
		var drop := speed * newfrict * delta # amount of speed to be reduced by friction.
		scaled_vel = input_vel * max(speed - drop, 0) / speed
	
	# snap to zero if slow enough.
	if speed < 0.1:
		return scaled_vel * 0
	
	return scaled_vel

func move_ground(input_vel: Vector3, delta: float) -> void:
	next_vel = Vector3.ZERO
	
	var speed : float = wishspeed
	
	if crouching or force_crouch:
		speed = wishslidespeed if sliding else wishcrouchspeed
		
		if sliding:
			if get_floor_angle() >= deg_to_rad(min_slide_angle):
				
			
			speed = wishslidespeed
		
		speed 
		#print(sliding)
	if sprinting:
		speed *= sprint_multiplier
	
	# first work on horiztonal.
	next_vel.x = input_vel.x
	next_vel.z = input_vel.z
	next_vel = friction(next_vel, delta)
	next_vel = accelerate(wishdir, next_vel, accel, speed, delta)
	
	# then vertical.
	next_vel.y = vertical_vel
	
	# launch off the floor.
	next_vel.y = -next_vel.dot(get_floor_normal())
	
	velocity = next_vel
	
	move_and_slide()


# accelerate without applying friction. ( with a lower allowed max_speed )
func move_air(input_vel: Vector3, delta: float) -> void:
	next_vel = Vector3.ZERO
	
	var airspeed : float = wishairspeed if total_vel < fastspeed else fastairspeed
	#print(airspeed)
	# print(airspeed)
	
	# first work on horiztonal.
	next_vel.x = input_vel.x
	next_vel.z = input_vel.z
	
	next_vel = accelerate(wishdir, next_vel, accel, airspeed, delta)
	
	# then vertical.
	next_vel.y = vertical_vel
	
	velocity = next_vel
	
	move_and_slide()

# set wish_jump if condition met.
func queue_jump() -> void:
	if auto_jump:
		wish_jump = Input.is_action_pressed("move_jump")
		
	elif Input.is_action_just_pressed("move_jump") and !wish_jump:
		wish_jump = true
		
	elif Input.is_action_just_released("move_jump"):
		wish_jump = false

func jump(delta: float) -> void:
	# zero coyote timer.
	coyote_timer = 0
	
	# disable floor snapping just for the jump.
	floor_snap_length = 0
	
	var impulse = jump_impulse
	
	# mega jump and zero its' timer.
	if always_mega_jump or mega_jump_charge == mega_jump_max_charge:
		impulse *= mega_jump_multiplier
		mega_jump_timer = 0
		
		# zero mega jump timers.
		mega_jump_timer  = 0
		mega_jump_charge = 0
	
	# apply impulse.
	vertical_vel = impulse
	
	move_air(velocity, delta) # mimic quake's first frame landing.
	wish_jump = false # player would need to press jump again.

func handle_sprint() -> void:
	if toggle_sprint:
		# if player stops moving, no more sprinting.
		if movedir.length() == 0:
			sprinting = false
			return
		
		# toggle sprint.
		if Input.is_action_just_pressed("move_sprint"):
			sprinting = !sprinting
		
	elif Input.is_action_just_pressed("move_sprint"):
		sprinting = true
	elif Input.is_action_just_released("move_sprint"):
		sprinting = false

func handle_crouch() -> void:
	if toggle_crouch:
		if Input.is_action_just_pressed("move_crouch"):
			crouching = !crouching
	
	elif Input.is_action_just_pressed("move_crouch"):
		crouching = true
	elif Input.is_action_just_released("move_crouch"):
		crouching = false
	
	var isbonk = (leadbonk.is_colliding() and leadbonk.get_collision_normal().dot(Vector3.DOWN) > 0) or bonk.is_colliding()
	var notstanding = collision.shape.height < stand_height - 0.2
	
	force_crouch = isbonk and notstanding





func _set_max_ramp_angle(value: float) -> void:
	floor_max_angle = deg_to_rad(max_ramp_angle)
