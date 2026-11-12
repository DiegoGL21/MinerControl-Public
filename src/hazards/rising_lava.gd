extends Area2D
## Origin is the lethal surface. The volume extends downwards, never pushes bodies.

const RESPAWN_ROLLBACK_DISTANCE := 36.0
const MIN_RESPAWN_LAVA_DISTANCE := 200.0
const MAX_RISE_SPEED := 30.0
const MAX_START_DELAY := 10.0
const RESPAWN_START_DELAY := 3.0

@export_range(0.0, MAX_RISE_SPEED, 0.5) var rise_speed: float = 20.0
@export_range(0.0, MAX_START_DELAY, 0.1) var start_delay: float = 5.0
@export var start_suspended := false
@export_node_path("CharacterBody2D") var player_path: NodePath
@export_node_path("Area2D") var start_trigger_path: NodePath
@export_node_path("Area2D") var finish_area_path: NodePath

var rising: bool = false
var activated: bool = false
var _completed: bool = false
var _respawning: bool = false
var _initial_cycle_started: bool = false
var _initial_position: Vector2
var _player: CharacterBody2D
@onready var _timer: Timer = $StartDelayTimer
@onready var _lava_loop: AudioStreamPlayer = $LavaLoop
@onready var _lava_death_sfx: AudioStreamPlayer = $LavaDeathSfx


func _ready() -> void:
	_validate_configuration()
	_initial_position = global_position
	_player = get_node_or_null(player_path) as CharacterBody2D
	if _player == null:
		push_error("RisingLava: configure the Player path.")
		set_physics_process(false)
		return
	body_entered.connect(_on_lava_body_entered)
	_timer.timeout.connect(_on_delay_finished)
	if start_suspended:
		activated = false
		rising = false
		_timer.stop()
	else:
		start_initial_cycle()
	var finish := get_node_or_null(finish_area_path) as Area2D
	if finish != null:
		finish.body_entered.connect(_on_level_finished)


func start_initial_cycle() -> void:
	if _initial_cycle_started or _completed or _respawning:
		return

	_initial_cycle_started = true
	activated = true
	_begin_rising_after_delay(start_delay)

func get_save_state() -> Dictionary:
	return {
		"lava_position_x": global_position.x,
		"lava_position_y": global_position.y,
		"lava_activated": activated,
		"lava_rising": rising,
		"lava_delay_remaining": _timer.time_left,
		"lava_completed": _completed,
	}


func restore_save_state(data: Dictionary) -> void:
	# Legacy saves have no lava snapshot and use the fixed scene position.
	if not data.has("lava_position_x"):
		start_initial_cycle()
		return
	_timer.stop()
	_initial_cycle_started = true
	global_position = Vector2(data["lava_position_x"], data["lava_position_y"])
	activated = data["lava_activated"]
	rising = data["lava_rising"]
	_completed = data.get("lava_completed", false)
	_respawning = false
	var remaining: float = data["lava_delay_remaining"]
	if _completed:
		_lava_loop.stop()
		return
	if not activated and not rising and remaining <= 0.0:
		_initial_cycle_started = false
		start_initial_cycle()
		return
	if activated and not rising and not _completed:
		if remaining > 0.0:
			_timer.start(remaining)
		else:
			# Snapshot taken on the timeout boundary: do not grant another full delay.
			rising = true
	if activated:
		_start_lava_loop()


func _physics_process(delta: float) -> void:
	if rising:
		global_position.y -= rise_speed * delta


func is_death_locked() -> bool:
	return _respawning


func _on_climb_started(body: Node2D) -> void:
	if body != _player or activated or _completed or _respawning:
		return
	start_initial_cycle()


func _on_delay_finished() -> void:
	if activated and not _completed and not _respawning:
		rising = true


func _on_lava_body_entered(body: Node2D) -> void:
	if body != _player or _respawning or _completed:
		return

	var level := get_parent()

	if (
		level != null
		and level.has_method("is_final_transition_active")
		and level.is_final_transition_active()
	):
		return

	_respawning = true
	rising = false
	_timer.stop()
	_lava_loop.stop()
	_lava_death_sfx.play()
	_player.velocity = Vector2.ZERO
	_player.set_physics_process(false)
	set_physics_process(false)
	var has_retry: bool = false
	if level != null and level.has_method("consume_life_for_retry"):
		has_retry = level.consume_life_for_retry()
	# Resolve respawn or the final visual death outside the overlap signal's query flush.
	_resolve_death.bind(has_retry, global_position.y).call_deferred()


func _resolve_death(has_retry: bool, death_lava_y: float) -> void:
	if _player.has_method("play_death_animation"):
		_player.call("play_death_animation")
		var death_sprite := _player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if death_sprite != null and death_sprite.animation == &"dying":
			await death_sprite.animation_finished
	if has_retry:
		_respawn_player(death_lava_y)
		return
	if _player.has_method("play_angel_animation"):
		_player.call("play_angel_animation")
		var angel_sprite := _player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if angel_sprite != null and angel_sprite.animation == &"angel":
			await angel_sprite.animation_finished
	_show_game_over()
	if _player.has_method("restore_angel_visual"):
		_player.call("restore_angel_visual")


func _respawn_player(death_lava_y: float) -> void:
	var level := get_parent()
	var respawn_position := _player.global_position
	if level != null and level.has_method("get_last_safe_position"):
		respawn_position = level.get_last_safe_position()
	_player.global_position = respawn_position
	_player.velocity = Vector2.ZERO
	if level != null and level.has_method("confirm_respawn_position"):
		level.confirm_respawn_position(respawn_position)
	var camera := _player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.reset_smoothing()
		camera.force_update_scroll()
	# Keep the existing fixed rollback before enforcing the minimum safe distance.
	var rollback_y := death_lava_y + RESPAWN_ROLLBACK_DISTANCE
	var minimum_safe_y := respawn_position.y + MIN_RESPAWN_LAVA_DISTANCE
	# maxf preserves the 36 px rollback and only moves the lava farther down if needed.
	global_position.y = maxf(rollback_y, minimum_safe_y)
	activated = true
	_begin_rising_after_delay(RESPAWN_START_DELAY)
	set_physics_process(true)
	if _player.has_method("finish_death_animation"):
		_player.call("finish_death_animation")
	_player.set_physics_process(true)
	_respawning = false
	_report_unsafe_respawn.call_deferred()


func _show_game_over() -> void:
	var level := get_parent()
	if level != null and level.has_method("show_game_over"):
		level.call("show_game_over")
		return
	push_error("RisingLava: Level01 no expone show_game_over().")


func _report_unsafe_respawn() -> void:
	await get_tree().physics_frame
	if not is_instance_valid(_player):
		return
	var player_bottom := _player.global_position.y
	var collision_shape := _player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape != null and collision_shape.shape is RectangleShape2D:
		var rectangle := collision_shape.shape as RectangleShape2D
		player_bottom += collision_shape.position.y + rectangle.size.y * 0.5
	var surface_clearance := global_position.y - player_bottom
	if overlaps_body(_player) or surface_clearance <= 0.0:
		push_warning("RisingLava: la separación de seguridad deja %.2f px entre la superficie y el Player." % surface_clearance)


func _validate_configuration() -> void:
	var valid_rise_speed := clampf(rise_speed, 0.0, MAX_RISE_SPEED)
	if not is_equal_approx(rise_speed, valid_rise_speed):
		push_warning("RisingLava: rise_speed debe estar entre 0 y %.1f; se ajusto el valor." % MAX_RISE_SPEED)
		rise_speed = valid_rise_speed
	var valid_start_delay := clampf(start_delay, 0.0, MAX_START_DELAY)
	if not is_equal_approx(start_delay, valid_start_delay):
		push_warning("RisingLava: start_delay debe estar entre 0 y %.1f; se ajusto el valor." % MAX_START_DELAY)
		start_delay = valid_start_delay


func _begin_rising_after_delay(delay: float = start_delay) -> void:
	_timer.stop()
	rising = false
	_start_lava_loop()

	if is_zero_approx(delay):
		rising = true
		return

	_timer.start(delay)


func _start_lava_loop() -> void:
	if not _completed and activated and not _lava_loop.playing:
		_lava_loop.play()


func reset() -> void:
	_timer.stop()
	_lava_loop.stop()
	_lava_death_sfx.stop()
	rising = false
	activated = false
	_initial_cycle_started = false
	_completed = false
	global_position = _initial_position


func _on_level_finished(body: Node2D) -> void:
	if body != _player or _respawning:
		return
	# Preserve the existing exit handler; only retire this hazard.
	reset()
	_completed = true
