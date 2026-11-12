extends CharacterBody2D

signal death_animation_finished

const SPEED = 200.0
const GRAVITY = 900.0
const MINE_DETECTOR_OFFSET := 28.0

const JUMP_START_ANIMATION := &"jump_start"
const NORMAL_JUMP_VELOCITY := -340.0
const MAX_JUMP_VELOCITY := -475.0
const MAX_CHARGE_TIME := 0.85
const MINING_COOLDOWN := 1.5

const AFK_STANDING_DELAY := 6.0
const AFK_REPEAT_DELAY := 10.0
const ANGEL_ASCENT_DISTANCE := 140.0


@export_range(0.0, 0.15, 0.01) var coyote_time := 0.09
@export_range(0.0, 0.20, 0.01) var jump_buffer_time := 0.10


@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var mine_detector: Area2D = $MineDetector
@onready var jump_sfx: AudioStreamPlayer = $JumpSfx


# 1 = derecha
# -1 = izquierda
var facing_direction := 1

var _mine_direction := 1
var _is_mining := false
var _mine_hit_applied := false
var _mining_cooldown_remaining := 0.0
var _is_dying := false

var _coyote_time_left := 0.0
var _jump_buffer_time_left := 0.0
var jump_charge_time := 0.0
var is_charging_jump := false
var _is_preparing_max_jump := false
var controls_enabled := true

var _afk_time := 0.0
var _standing_playing := false
var _standing_has_played := false
var _angel_visual_origin := Vector2.ZERO
var _angel_visual_scale := Vector2.ONE
var _angel_visual_z_index := 0
var _angel_tween: Tween


func _ready() -> void:
	_angel_visual_origin = sprite.position
	_angel_visual_scale = sprite.scale
	_angel_visual_z_index = sprite.z_index
	sprite.frame_changed.connect(_on_sprite_frame_changed)
	sprite.animation_finished.connect(_on_sprite_animation_finished)
	_update_mine_detector()


func _physics_process(delta: float) -> void:
	if _is_dying:
		return
	_update_mining_cooldown(delta)

	var was_on_floor := is_on_floor()
	var direction := (
		Input.get_axis("move_left", "move_right")
		if controls_enabled
		else 0.0
	)

	_update_jump_timers(delta, was_on_floor)
	_apply_gravity(delta, was_on_floor)

	if not controls_enabled:
		_reset_jump_state()
		_reset_afk()
		velocity.x = 0.0
		_update_mine_detector()
		move_and_slide()
		if not _is_mining:
			update_animation(0.0)
		return

	if (
		_is_mining
		and (
			not is_zero_approx(direction)
			or Input.is_action_just_pressed(&"jump")
		)
	):
		_cancel_mining()

	_handle_max_jump_preparation(was_on_floor, direction)
	_handle_jump_input(delta, was_on_floor, direction)

	# Detectar movimiento izquierda y derecha.
	if direction != 0.0 and not _is_mining:
		facing_direction = 1 if direction > 0.0 else -1
		sprite.flip_h = facing_direction < 0

	# Cualquier acción cancela Standing inmediatamente.
	if _standing_playing and (
		direction != 0.0
		or Input.is_action_just_pressed("jump")
		or Input.is_action_just_pressed("mine")
	):
		_standing_playing = false
		_afk_time = 0.0

	_update_afk_animation(delta, direction)

	# Movimiento horizontal.
	if _is_mining:
		velocity.x = 0.0
	elif is_charging_jump or _is_preparing_max_jump:
		velocity.x = 0.0
	elif direction != 0.0:
		velocity.x = direction * SPEED
	else:
		velocity.x = 0.0

	# Minería.
	if (
		Input.is_action_just_pressed("mine")
		and not _is_mining
		and _mining_cooldown_remaining <= 0.0
		and not is_charging_jump
		and not _is_preparing_max_jump
	):
		_start_mining()

	if _is_mining:
		sprite.flip_h = _mine_direction < 0
	else:
		sprite.flip_h = facing_direction < 0

	_update_mine_detector()

	move_and_slide()

	if not _is_mining and not _standing_playing:
		update_animation(direction)


func get_facing_direction() -> int:
	return 1 if facing_direction >= 0 else -1


func set_facing_direction(value: int) -> void:
	facing_direction = -1 if value < 0 else 1
	_mine_direction = facing_direction
	sprite.flip_h = facing_direction < 0
	_update_mine_detector()


func _update_jump_timers(delta: float, was_on_floor: bool) -> void:
	if was_on_floor:
		_coyote_time_left = coyote_time
	else:
		_coyote_time_left = maxf(_coyote_time_left - delta, 0.0)

	_jump_buffer_time_left = maxf(_jump_buffer_time_left - delta, 0.0)


func _apply_gravity(delta: float, was_on_floor: bool) -> void:
	if was_on_floor:
		return

	velocity.y += GRAVITY * delta


func _handle_max_jump_preparation(
	was_on_floor: bool,
	direction: float
) -> void:
	if _is_preparing_max_jump:
		if (
			not was_on_floor
			or not is_zero_approx(direction)
			or not Input.is_action_pressed(&"max_jump_modifier")
			or Input.is_action_just_pressed(&"mine")
			or _is_mining
			or _is_dying
			or get_tree().paused
			or _is_final_transition_active()
		):
			_cancel_max_jump_preparation()
		return

	if (
		Input.is_action_just_pressed(&"max_jump_modifier")
		and _can_prepare_maximum_jump(was_on_floor, direction)
	):
		_start_max_jump_preparation()


func _handle_jump_input(
	delta: float,
	was_on_floor: bool,
	direction: float
) -> void:
	var jump_just_pressed := Input.is_action_just_pressed(&"jump")

	if jump_just_pressed:
		_reset_afk()

		if _can_start_maximum_jump(was_on_floor, direction):
			_start_jump_charge()
		elif _coyote_time_left > 0.0:
			_perform_jump(false)
		elif was_on_floor:
			_perform_jump(false)
		else:
			_jump_buffer_time_left = jump_buffer_time

	if is_charging_jump:
		if (
			not was_on_floor
			or not is_zero_approx(direction)
			or not Input.is_action_pressed(&"jump")
			or not Input.is_action_pressed(&"max_jump_modifier")
			or _is_mining
			or _is_dying
			or get_tree().paused
			or _is_final_transition_active()
		):
			_cancel_jump_charge()
			return

		jump_charge_time = minf(
			jump_charge_time + delta,
			MAX_CHARGE_TIME
		)
		_update_jump_charge_visual()

		if jump_charge_time >= MAX_CHARGE_TIME:
			_perform_jump(true)

		return

	if was_on_floor and _jump_buffer_time_left > 0.0:
		_perform_jump(false)


func _can_start_maximum_jump(
	was_on_floor: bool,
	direction: float
) -> bool:
	return (
		was_on_floor
		and is_zero_approx(direction)
		and Input.is_action_pressed(&"max_jump_modifier")
		and not _is_mining
		and not _is_dying
		and not get_tree().paused
		and not _is_final_transition_active()
		and is_zero_approx(_jump_buffer_time_left)
	)


func _can_prepare_maximum_jump(
	was_on_floor: bool,
	direction: float
) -> bool:
	return (
		controls_enabled
		and was_on_floor
		and is_zero_approx(direction)
		and not _is_mining
		and not _is_dying
		and not get_tree().paused
		and not _is_final_transition_active()
	)


func _is_final_transition_active() -> bool:
	var current_scene := get_tree().current_scene
	return (
		current_scene != null
		and current_scene.has_method("is_final_transition_active")
		and current_scene.is_final_transition_active()
	)


func _start_jump_charge() -> void:
	_reset_afk()
	_is_preparing_max_jump = false
	is_charging_jump = true
	jump_charge_time = 0.0
	velocity.x = 0.0
	_jump_buffer_time_left = 0.0

	if not _is_mining:
		sprite.flip_h = facing_direction < 0
		_update_jump_charge_visual()


func _start_max_jump_preparation() -> void:
	_reset_afk()
	_is_preparing_max_jump = true
	velocity.x = 0.0
	_show_jump_start_initial_frame()


func _show_jump_start_initial_frame() -> void:
	var frame_count := sprite.sprite_frames.get_frame_count(
		JUMP_START_ANIMATION
	)
	if frame_count <= 0:
		return
	var initial_visual_frame := mini(7, frame_count - 1)

	if sprite.animation != JUMP_START_ANIMATION:
		sprite.play(JUMP_START_ANIMATION)

	sprite.pause()
	sprite.frame = initial_visual_frame


func _update_jump_charge_visual() -> void:
	var frame_count := sprite.sprite_frames.get_frame_count(
		JUMP_START_ANIMATION
	)
	if frame_count <= 0:
		return
	var initial_visual_frame := mini(7, frame_count - 1)

	var charge_ratio := clampf(
		jump_charge_time / MAX_CHARGE_TIME,
		0.0,
		1.0
	)
	var frame_index := maxi(
		initial_visual_frame,
		mini(
			floori(charge_ratio * float(frame_count) + 0.000001),
			frame_count - 1
		)
	)

	if sprite.animation != JUMP_START_ANIMATION:
		sprite.play(JUMP_START_ANIMATION)

	sprite.pause()
	sprite.frame = frame_index


func _perform_jump(use_maximum_force: bool) -> void:
	velocity.y = (
		MAX_JUMP_VELOCITY
		if use_maximum_force
		else NORMAL_JUMP_VELOCITY
	)
	jump_sfx.play()
	_coyote_time_left = 0.0
	_jump_buffer_time_left = 0.0
	_is_preparing_max_jump = false
	is_charging_jump = false
	jump_charge_time = 0.0

	if not _is_mining:
		sprite.flip_h = facing_direction < 0
		sprite.play(&"jump_air")


func _cancel_jump_charge() -> void:
	is_charging_jump = false
	jump_charge_time = 0.0


func _cancel_max_jump_preparation() -> void:
	_is_preparing_max_jump = false


func cancel_jump_charge_for_pause() -> void:
	if not is_charging_jump and not _is_preparing_max_jump:
		return

	_cancel_jump_charge()
	_cancel_max_jump_preparation()
	velocity.x = 0.0

	if not _is_mining and not _is_dying:
		update_animation(0.0)


func _reset_jump_state() -> void:
	_cancel_jump_charge()
	_cancel_max_jump_preparation()
	_coyote_time_left = 0.0
	_jump_buffer_time_left = 0.0


func update_animation(direction: float) -> void:
	if _is_preparing_max_jump:
		sprite.flip_h = facing_direction < 0
		_show_jump_start_initial_frame()
		return

	if is_charging_jump:
		sprite.flip_h = facing_direction < 0
		_update_jump_charge_visual()
		return

	# Personaje en el aire.
	if not is_on_floor():
		sprite.flip_h = facing_direction < 0

		# Subiendo.
		if velocity.y < 0.0:
			if sprite.animation != &"jump_air":
				sprite.play(&"jump_air")

		# Cayendo.
		else:
			if sprite.animation != &"jump_fall":
				sprite.play(&"jump_fall")

	# Caminando hacia la derecha.
	elif direction > 0.0:
		sprite.flip_h = false

		if sprite.animation != &"walk":
			sprite.play(&"walk")

	# Caminando hacia la izquierda.
	elif direction < 0.0:
		sprite.flip_h = true

		if sprite.animation != &"walk":
			sprite.play(&"walk")

	# Quieto mirando a la derecha.
	elif facing_direction > 0:
		sprite.flip_h = false

		if sprite.animation != &"idle_right":
			sprite.play(&"idle_right")

	# Quieto mirando a la izquierda.
	else:
		sprite.flip_h = false

		if sprite.animation != &"idle_left":
			sprite.play(&"idle_left")


func play_death_animation() -> void:
	if _is_dying:
		return

	restore_angel_visual()
	_is_dying = true
	_is_mining = false

	_reset_afk()
	_reset_jump_state()

	velocity = Vector2.ZERO
	sprite.flip_h = false
	sprite.play(&"dying")


func play_angel_animation() -> void:
	restore_angel_visual()
	_angel_visual_origin = sprite.position
	_angel_visual_scale = sprite.scale
	_angel_visual_z_index = sprite.z_index
	_is_dying = true
	_is_mining = false

	_reset_afk()
	_reset_jump_state()

	velocity = Vector2.ZERO
	sprite.flip_h = false
	# Angel uses the complete 32x32 canvas at an exact 2x scale.
	sprite.scale = Vector2(2.0, 2.0)
	# Keep the spirit above the lava surface that triggered the final death.
	sprite.z_index = 2
	sprite.play(&"angel")

	var frame_count := sprite.sprite_frames.get_frame_count(&"angel")
	var frames_per_second := sprite.sprite_frames.get_animation_speed(&"angel")
	var animation_duration := float(frame_count) / frames_per_second
	_angel_tween = create_tween()
	_angel_tween.set_trans(Tween.TRANS_SINE)
	_angel_tween.set_ease(Tween.EASE_IN_OUT)
	_angel_tween.tween_property(
		sprite,
		"position",
		_angel_visual_origin + Vector2.UP * ANGEL_ASCENT_DISTANCE,
		animation_duration
	)


func restore_angel_visual() -> void:
	if _angel_tween != null and _angel_tween.is_valid():
		_angel_tween.kill()

	_angel_tween = null
	sprite.position = _angel_visual_origin
	sprite.scale = _angel_visual_scale
	sprite.z_index = _angel_visual_z_index


func finish_death_animation() -> void:
	restore_angel_visual()
	_is_dying = false
	_mining_cooldown_remaining = 0.0

	_reset_afk()
	_reset_jump_state()

	sprite.flip_h = facing_direction < 0

	sprite.play(
		&"idle_right"
		if facing_direction > 0
		else &"idle_left"
	)


func _update_mining_cooldown(delta: float) -> void:
	_mining_cooldown_remaining = maxf(
		_mining_cooldown_remaining - delta,
		0.0
	)


func _start_mining() -> void:
	_reset_afk()
	velocity.x = 0.0
	_mining_cooldown_remaining = MINING_COOLDOWN

	_is_mining = true
	_mine_hit_applied = false

	_mine_direction = 1 if facing_direction >= 0 else -1

	sprite.flip_h = _mine_direction < 0

	_update_mine_detector()

	sprite.play(&"mining")


func _cancel_mining() -> void:
	if not _is_mining:
		return

	_is_mining = false
	_mine_hit_applied = true

	if sprite.animation == &"mining":
		sprite.stop()


func _update_mine_detector() -> void:
	var direction := (
		_mine_direction
		if _is_mining
		else (1 if facing_direction >= 0 else -1)
	)

	mine_detector.position.x = MINE_DETECTOR_OFFSET * direction


func _on_sprite_frame_changed() -> void:
	if (
		not _is_mining
		or sprite.animation != &"mining"
		or sprite.frame != 2
		or _mine_hit_applied
	):
		return

	_mine_hit_applied = true
	_apply_mine_hit()


func _apply_mine_hit() -> void:
	var closest_target: Node2D
	var closest_distance := INF

	var candidates: Array[Node2D] = []

	for area in mine_detector.get_overlapping_areas():
		candidates.append(area)

	for body in mine_detector.get_overlapping_bodies():
		candidates.append(body)

	for candidate in candidates:
		if (
			not candidate.is_in_group(&"mineable")
			or not candidate.has_method(&"receive_mine_hit")
		):
			continue

		var distance := global_position.distance_squared_to(
			candidate.global_position
		)

		if distance < closest_distance:
			closest_distance = distance
			closest_target = candidate

	if closest_target != null:
		closest_target.receive_mine_hit()


func _on_sprite_animation_finished() -> void:
	if sprite.animation == &"mining":
		_is_mining = false

		update_animation(
			Input.get_axis("move_left", "move_right")
		)

	elif sprite.animation == &"dying":
		death_animation_finished.emit()

	elif sprite.animation == &"standing":
		_standing_playing = false
		_afk_time = 0.0

		if facing_direction > 0:
			sprite.play(&"idle_right")
		else:
			sprite.play(&"idle_left")


func _update_afk_animation(delta: float, direction: float) -> void:
	# Solo acumular AFK estando realmente quieto y en el suelo.
	if (
		_is_dying
		or _is_mining
		or _is_preparing_max_jump
		or is_charging_jump
		or not controls_enabled
		or not is_on_floor()
		or direction != 0.0
	):
		_reset_afk()
		return

	# Cualquier input evita que se considere AFK.
	if (
		Input.is_action_pressed("move_left")
		or Input.is_action_pressed("move_right")
		or Input.is_action_pressed("jump")
		or Input.is_action_pressed("mine")
	):
		_reset_afk()
		return

	if _standing_playing:
		return

	_afk_time += delta

	var required_time := (
		AFK_REPEAT_DELAY
		if _standing_has_played
		else AFK_STANDING_DELAY
	)

	if _afk_time >= required_time:
		_standing_playing = true
		_standing_has_played = true
		_afk_time = 0.0

		sprite.flip_h = facing_direction < 0
		sprite.play(&"standing")


func _reset_afk() -> void:
	_afk_time = 0.0
	_standing_playing = false
	_standing_has_played = false


func set_controls_enabled(value: bool) -> void:
	controls_enabled = value

	if controls_enabled:
		return

	_reset_jump_state()
	_reset_afk()
	velocity.x = 0.0
