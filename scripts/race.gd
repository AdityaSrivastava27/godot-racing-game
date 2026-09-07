extends Node3D

## Minimum race loop: bind controls, place the car, count down, then enable driving.

enum Phase { COUNTDOWN, RACING }

@export var countdown_seconds: float = 3.0

var _phase: Phase = Phase.COUNTDOWN
var _time_left: float = 3.0
var _go_display: float = 0.0

@onready var _track = $Track
@onready var _car = $PlayerCar
@onready var _camera = $FollowCamera
@onready var _countdown_label: Label = $HUD/CountdownLabel
@onready var _speed_label: Label = $HUD/SpeedLabel
@onready var _hint_label: Label = $HUD/HintLabel


func _ready() -> void:
	_ensure_input_actions()
	_time_left = countdown_seconds
	_car.global_transform = _track.get_start_transform()
	_car.controls_enabled = false
	_camera.target = _car
	_camera.snap_to_target()
	_hint_label.visible = true
	_speed_label.text = "0 km/h"


func _process(delta: float) -> void:
	_speed_label.text = "%d km/h" % int(round(_car.get_speed_kph()))

	match _phase:
		Phase.COUNTDOWN:
			_time_left -= delta
			if _time_left > 0.0:
				_countdown_label.text = str(ceili(_time_left))
			else:
				_phase = Phase.RACING
				_car.controls_enabled = true
				_go_display = 1.1
				_countdown_label.text = "GO"
				_hint_label.visible = false
		Phase.RACING:
			if _go_display > 0.0:
				_go_display -= delta
				if _go_display <= 0.0:
					_countdown_label.text = ""


func _ensure_input_actions() -> void:
	_ensure_action("accelerate", [KEY_W, KEY_UP])
	_ensure_action("brake", [KEY_S, KEY_DOWN])
	_ensure_action("steer_left", [KEY_A, KEY_LEFT])
	_ensure_action("steer_right", [KEY_D, KEY_RIGHT])
	_ensure_joy_axis("steer_left", JOY_AXIS_LEFT_X, -1.0)
	_ensure_joy_axis("steer_right", JOY_AXIS_LEFT_X, 1.0)
	_ensure_joy_axis("accelerate", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_ensure_joy_axis("brake", JOY_AXIS_TRIGGER_LEFT, 1.0)


func _ensure_action(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for keycode in keys:
		if _has_key_binding(action, keycode):
			continue
		var event := InputEventKey.new()
		event.physical_keycode = keycode as Key
		InputMap.action_add_event(action, event)


func _ensure_joy_axis(action: StringName, axis: JoyAxis, axis_value: float) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for existing in InputMap.action_get_events(action):
		var motion := existing as InputEventJoypadMotion
		if motion and motion.axis == axis and is_equal_approx(motion.axis_value, axis_value):
			return
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = axis_value
	InputMap.action_add_event(action, event)


func _has_key_binding(action: StringName, keycode: int) -> bool:
	for existing in InputMap.action_get_events(action):
		var key := existing as InputEventKey
		if key and key.physical_keycode == keycode:
			return true
	return false
