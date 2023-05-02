extends CharacterBody3D


# https://www.youtube.com/watch?v=M3VnsRIPlck
# https://www.youtube.com/watch?v=v3zT3Z5apaM
# https://github.com/axel37/godot-quake-movement/blob/main/Player.gd

@export var look_sens := Vector2(0.001, 0.001)
@export var auto_jump    := false # auto bhop.

@export var toggle_crouch := false
@export var toggle_sprint := false

@export var wishspeed       : float =   6.0 # metres per second.
@export var wishcrouchspeed : float =   3.0
@export var wishairspeed    : float =   3.0
@export var wishslidespeed  : float =   0.1 # control spee while sliding
@export var fastairspeed    : float =   0.1 # control speed in air when going fast
@export var accel           : float = 100.0 # or max_speed * 10 = 1/10th of a second.
@export var frict           : float =   7.0 # higher = less slippy - in quake-based games, usually 1-5.
@export var max_ramp_angle  : float =  45.0 : set = _set_max_ramp_angle # max angle player can go up at full speed.
@export var fastspeed       : float =  10.5 # how fast is fast, dictates behaviour like fastairspeed

@export var grav         : float = ProjectSettings.get_setting("physics/3d/default_gravity")
@export var jump_impulse : float = 4.8

@export var sprint_multiplier : float =  1.5
@export var crouch_speed      : float = 20.0
@export var stand_height      : float =  2.261 # height while standing.
@export var crouch_height     : float =  1.2 # height while crouching.

@export var head_crouch_height : float = 1.2
@export var head_stand_height  : float = 2.346

@export var slidefrict   : float = 1.0
@export var slidespeed   : float = 6.0

@export var slopesnap    : float =  1.0
@export var coyote_time  : float =  0.35
@export var slipspeed    : float = 10.5
@export var slipspeedmax : float = 16.0
@export var slipfrict    : float =  1.0

@onready var head      := $Head
@onready var camera    := $Head/Camera
@onready var collision := $Collision

var player_control := true

var terminal_vel : float = grav * -5 # when reached, stop increasing fall speed.

var movedir  := Vector2.ZERO
var wishdir  := Vector3.ZERO
var next_vel := Vector3.ZERO

var vertical_vel  : float = 0.0
var current_speed : float = 0.0
var add_speed     : float = 0.0
var total_vel     : float = 0.0

var sprinting    := false # is player sprinting?
var crouching    := false # is player crouching?
var force_crouch := false # is player forced to crouch? are they in an area where they can't stand up?
var sliding      := false # is player sliding?
var wish_jump    := false # is player jump queued? jump key can be held before hitting the ground.
var coyote_timer := coyote_time





func _ready() -> void:
	pass



func _physics_process(delta) -> void:
	total_vel = velocity.length()
	#print(total_vel)
	if player_control:
		movedir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward").normalized()
	else:
		movedir = Vector2.ZERO
	
	# wishdir is our normalized horizontal input.
	wishdir = Vector3(movedir.x, 0, movedir.y).rotated(Vector3.UP, self.global_transform.basis.get_euler().y).normalized()
	
	if player_control:
		queue_jump()
		handle_sprint()
		handle_crouch()
	
	# clamp height.
	collision.shape.height = clamp(collision.shape.height, crouch_height, stand_height)
	
	# movement.
	if is_on_floor():
		coyote_timer = coyote_time
		
		if wish_jump: # if we're on the ground, but this is true, we've just landed.
			floor_snap_length = 0.0
			jump(delta)
		
		else:
			floor_snap_length = slopesnap
			move_ground(velocity, delta)
			
			if is_on_floor(): # launch off the floor.
				vertical_vel = -velocity.dot(get_floor_normal())
	
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
	
	# crouching.
	if crouching:
		collision.shape.height = lerp(collision.shape.height, crouch_height, crouch_speed * delta)
	else:
		collision.shape.height += crouch_speed * delta
	
	if Input.is_action_just_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	# Camera rotation.
	if event is InputEventMouseMotion && player_control:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			rotate_y(-event.relative.x * look_sens.x)
			head.rotate_x(-event.relative.y * look_sens.y)
			
			head.rotation.x = clamp(head.rotation.x, -PI/2, PI/2)
	elif event is InputEventMouseButton && Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
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
		
		if min(max(speed - slipspeed, 0), slipspeedmax - slipspeed) / (slipspeedmax - slipspeed) > 0:
			newfrict = slipfrict
		elif crouching:
			if speed >= slidespeed:
				newfrict = slidefrict
				sliding = true
		
		var drop := speed * newfrict * delta # amount of speed to be reduced by friction.
		scaled_vel = input_vel * max(speed - drop, 0) / speed
	
	# snap to zero if slow enough.
	if speed < 0.1:
		return scaled_vel * 0
	
	return scaled_vel

func move_ground(input_vel: Vector3, delta: float) -> void:
	next_vel = Vector3.ZERO
	
	var speed : float = wishspeed
	
	if crouching:
		speed = wishslidespeed if sliding else wishcrouchspeed
	if sprinting:
		speed *= sprint_multiplier
	
	# first work on horiztonal.
	next_vel.x = input_vel.x
	next_vel.z = input_vel.z
	next_vel = friction(next_vel, delta)
	next_vel = accelerate(wishdir, next_vel, accel, speed, delta)
	
	# then vertical.
	next_vel.y = vertical_vel
	
	velocity = next_vel
	
	move_and_slide()


# accelerate without applying friction. ( with a lower allowed max_speed )
func move_air(input_vel: Vector3, delta: float) -> void:
	next_vel = Vector3.ZERO
	
	var airspeed : float = wishairspeed if total_vel < fastspeed else fastairspeed
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
	coyote_timer = 0
	floor_snap_length = 0 # disable snapping just for the jump.
	vertical_vel += jump_impulse
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






func _set_max_ramp_angle(value: float) -> void:
	floor_max_angle = deg_to_rad(max_ramp_angle)
