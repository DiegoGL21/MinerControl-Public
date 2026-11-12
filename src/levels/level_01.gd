extends Node2D
## Coordinates are explicit so changing a TileMap cannot silently move a save checkpoint.

const SAFE_CONTACT_FRAMES := 1
const SAFE_RESPAWN_OFFSET := Vector2(0.0, -2.0)
const SAFE_SEARCH_RADIUS := 96.0
const SAFE_SURFACE_DISTANCE := 20.0

var checkpoints: Dictionary = {}
var active_phase: int = 1
var last_safe_position: Vector2
var _safe_floor_id: int = 0
var _safe_contact_frames: int = 0
var _safe_candidate_position: Vector2
var _safe_candidate_confirmed: bool = false
var _final_transition_active: bool = false
var _is_restoring_save: bool = false

var current_lives: int:
	get:
		return SaveManager.life

@onready var player: CharacterBody2D = $Phase01/Player
@onready var _heart_slot: Control = $LivesHUD/HeartSlot
@onready var _heart_animation: AnimatedSprite2D = $LivesHUD/HeartSlot/HeartAnimation
@onready var _controls_tutorial: CanvasLayer = $ControlsTutorial
@onready var _rising_lava: Area2D = $RisingLava
@onready var _mineral_collected_sfx: AudioStreamPlayer = $MineralCollectedSfx
@onready var fade_in: ColorRect = $TransitionLayer/FadeIn


func _ready() -> void:
	var is_loading := not SaveManager.pending_load.is_empty()
	_is_restoring_save = is_loading

	# Run after Player physics so a valid landing is recorded on that same frame.
	process_physics_priority = player.process_physics_priority + 1
	_heart_animation.animation_finished.connect(_on_heart_animation_finished)
	_controls_tutorial.connect(&"tutorial_started", _on_controls_tutorial_started)
	_connect_mineral_sfx()

	# Inicia la transición visual de entrada al nivel.
	_play_fade_in()

	last_safe_position = player.global_position

	checkpoints = {
		1: $SaveCheckpoints/Phase1.global_position,
		2: $SaveCheckpoints/Phase2.global_position,
		3: $SaveCheckpoints/Phase3.global_position,
	}

	$Phase01/ExitArea.body_entered.connect(_on_phase_entered.bind(2))
	$Phase02/ExitArea.body_entered.connect(_on_phase_entered.bind(3))

	if is_loading:
		_controls_tutorial.hide_tutorial()
		_set_player_controls_enabled(true)

		var data := SaveManager.pending_load.duplicate()
		SaveManager.pending_load.clear()

		set_lives(int(data["life"]))
		SaveManager.minerals = data["minerals"]

		player.set_physics_process(false)
		$RisingLava.set_physics_process(false)
		$RisingLava.monitoring = false

		_restore_saved_position.call_deferred(data)
	else:
		SaveManager.new_game()
		_update_lives_hud()
		_set_player_controls_enabled(false)
		_controls_tutorial.show_tutorial()


func _connect_mineral_sfx() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"mineable"):
		if (
			node.has_signal(&"mineral_collected")
			and not node.is_connected(
				&"mineral_collected",
				_on_mineral_collected
			)
		):
			node.connect(
				&"mineral_collected",
				_on_mineral_collected
			)


func _on_mineral_collected() -> void:
	_mineral_collected_sfx.play()


func _on_controls_tutorial_started() -> void:
	_controls_tutorial.hide_tutorial()
	_set_player_controls_enabled(true)

	if _rising_lava.has_method("start_initial_cycle"):
		_rising_lava.call("start_initial_cycle")


func _set_player_controls_enabled(value: bool) -> void:
	if player.has_method("set_controls_enabled"):
		player.call("set_controls_enabled", value)


func _on_phase_entered(body: Node2D, phase: int) -> void:
	if body != player or _is_death_locked():
		return

	_set_active_phase(phase)


func _physics_process(_delta: float) -> void:
	if _is_restoring_save or _is_death_locked():
		return

	# ExitArea can be bypassed by boarding a transition platform farther along its path.
	# Crossing a phase's horizontal boundary is the authoritative phase change.
	_set_active_phase(_phase_at_position(player.global_position))
	_update_last_safe_position()


func _set_active_phase(phase: int) -> void:
	if phase <= active_phase:
		return

	active_phase = phase


func _phase_at_position(target_position: Vector2) -> int:
	if target_position.y + 32.0 < -720.0:
		return 3

	if target_position.y + 32.0 < 0.0:
		return 2

	return 1


func set_lives(value: int, animate_loss: bool = false) -> void:
	SaveManager.life = clampi(value, 0, SaveManager.MAX_LIVES)
	_update_lives_hud(animate_loss)


func consume_life_for_retry() -> bool:
	if current_lives <= 0:
		return false

	set_lives(current_lives - 1, true)
	return current_lives > 0


func show_game_over() -> void:
	$ControlsTutorial.hide_tutorial()
	$MineralCounter.visible = false
	$PauseUI.visible = false
	$PauseUI.process_mode = Node.PROCESS_MODE_DISABLED
	_heart_animation.stop()
	_heart_slot.visible = false
	$GameOver.show_game_over()


func can_pause_gameplay() -> bool:
	return (
		not _is_restoring_save
		and not _is_death_locked()
		and not _final_transition_active
		and not $GameOver.visible
	)


func prepare_player_for_pause() -> void:
	if player.has_method("cancel_jump_charge_for_pause"):
		player.call("cancel_jump_charge_for_pause")


func try_begin_final_transition() -> bool:
	if (
		_final_transition_active
		or _is_death_locked()
		or $GameOver.visible
	):
		return false

	_final_transition_active = true
	get_tree().paused = false
	$PauseUI.visible = false
	$PauseUI.process_mode = Node.PROCESS_MODE_DISABLED
	return true


func cancel_final_transition() -> void:
	if not _final_transition_active:
		return

	_final_transition_active = false
	$PauseUI.process_mode = Node.PROCESS_MODE_ALWAYS
	$PauseUI.visible = true
	$PauseUI/PausePanel.visible = false
	$PauseUI/PauseButton.visible = true


func is_final_transition_active() -> bool:
	return _final_transition_active


func mark_level_01_completed() -> bool:
	SaveManager.level_01_completed = true
	return SaveManager.save_game()


func _update_lives_hud(animate_loss: bool = false) -> void:
	if animate_loss and current_lives == 1:
		_heart_slot.visible = true
		_heart_animation.play(&"lose_first_heart")
		return

	if animate_loss and current_lives <= 0:
		_heart_slot.visible = true
		_heart_animation.play(&"dying")
		return

	if current_lives >= 2:
		_play_stable_life_animation(&"full_health")
	elif current_lives == 1:
		_play_stable_life_animation(&"one_heart_left")

	else:
		_heart_animation.stop()
		_heart_slot.visible = false


func _on_heart_animation_finished() -> void:
	if _heart_animation.animation == &"lose_first_heart":
		_update_lives_hud()
	elif _heart_animation.animation == &"dying":
		_update_lives_hud()


func _play_stable_life_animation(animation_name: StringName) -> void:
	_heart_slot.visible = true

	if (
		_heart_animation.animation != animation_name
		or not _heart_animation.is_playing()
	):
		_heart_animation.play(animation_name)


func _update_last_safe_position() -> void:
	var floor_collider := _get_fixed_floor_collider()

	if (
		floor_collider == null
		or not is_zero_approx(player.velocity.y)
		or $RisingLava.overlaps_body(player)
	):
		_reset_safe_candidate()
		return

	var floor_id := floor_collider.get_instance_id()

	if floor_id != _safe_floor_id:
		_safe_floor_id = floor_id
		_safe_contact_frames = 0
		_safe_candidate_position = player.global_position + SAFE_RESPAWN_OFFSET
		_safe_candidate_confirmed = false

	if _safe_candidate_confirmed:
		return

	_safe_contact_frames += 1

	if _safe_contact_frames < SAFE_CONTACT_FRAMES:
		return

	if _is_position_clear(_safe_candidate_position):
		last_safe_position = _safe_candidate_position
		_safe_candidate_confirmed = true


func _get_fixed_floor_collider() -> Object:
	if not player.is_on_floor() or not player.is_physics_processing():
		return null

	var fixed_floor: Object = null

	for index in range(player.get_slide_collision_count()):
		var collision := player.get_slide_collision(index)

		if collision.get_normal().dot(Vector2.UP) < 0.7:
			continue

		var collider := collision.get_collider()

		if collider is AnimatableBody2D:
			return null

		if collider != null and fixed_floor == null:
			fixed_floor = collider

	return fixed_floor


func _reset_safe_candidate() -> void:
	_safe_floor_id = 0
	_safe_contact_frames = 0
	_safe_candidate_confirmed = false


func get_last_safe_position() -> Vector2:
	return last_safe_position


func get_phase_at_position(target_position: Vector2) -> int:
	return _phase_at_position(target_position)


func get_active_phase() -> int:
	return active_phase


func confirm_respawn_position(target_position: Vector2) -> void:
	_set_active_phase(_phase_at_position(target_position))
	last_safe_position = target_position
	_reset_safe_candidate()


func _find_nearby_safe_position(origin: Vector2, phase: int) -> Dictionary:
	var offsets: Array[Vector2] = []

	for distance: float in [
		4.0,
		8.0,
		12.0,
		16.0,
		24.0,
		32.0,
		48.0,
		64.0,
		80.0,
		96.0
	]:
		offsets.append(Vector2.UP * distance)
		offsets.append(Vector2.LEFT * distance)
		offsets.append(Vector2.RIGHT * distance)

		var raised_distance := minf(distance, 16.0)

		for direction: float in [-1.0, 1.0]:
			var diagonal := Vector2(
				direction * distance,
				-raised_distance
			)

			if diagonal.length() <= SAFE_SEARCH_RADIUS:
				offsets.append(diagonal)

	offsets.sort_custom(
		func(a: Vector2, b: Vector2) -> bool:
			return a.length_squared() < b.length_squared()
	)

	for offset in offsets:
		var candidate := origin + offset

		if _is_valid_dynamic_respawn(candidate, phase):
			return {
				"position": candidate
			}

	return {}


func _is_valid_dynamic_respawn(target: Vector2, phase: int) -> bool:
	return (
		_phase_at_position(target) == phase
		and _is_position_clear(target)
		and _is_position_above_lava(target)
		and _has_fixed_surface_below(target)
	)


func _is_position_above_lava(target: Vector2) -> bool:
	return (
		target.y + _player_bottom_offset()
		< $RisingLava.global_position.y
	)


func _has_fixed_surface_below(target: Vector2) -> bool:
	var player_bottom := _player_bottom_offset()

	var ray := PhysicsRayQueryParameters2D.create(
		target + Vector2(0.0, player_bottom - 1.0),
		target + Vector2(0.0, player_bottom + SAFE_SURFACE_DISTANCE),
		player.collision_mask,
		[player.get_rid()]
	)

	ray.collide_with_bodies = true
	ray.collide_with_areas = false

	var hit := get_world_2d().direct_space_state.intersect_ray(ray)

	return (
		not hit.is_empty()
		and not hit.get("collider") is AnimatableBody2D
	)


func _player_bottom_offset() -> float:
	var collision_shape := (
		player.get_node_or_null("CollisionShape2D")
		as CollisionShape2D
	)

	if (
		collision_shape != null
		and collision_shape.shape is RectangleShape2D
	):
		var rectangle := collision_shape.shape as RectangleShape2D

		return (
			collision_shape.position.y
			+ rectangle.size.y * 0.5
		)

	return 32.0


func _is_death_locked() -> bool:
	return (
		$RisingLava.has_method("is_death_locked")
		and $RisingLava.is_death_locked()
	)


func _restore_saved_position(data: Dictionary) -> void:
	# All phase/Player _ready callbacks have completed before this deferred restoration.
	var phase: int = data["phase"]

	active_phase = phase

	var load_position: Vector2 = checkpoints.get(
		phase,
		checkpoints[1]
	)
	var safe_respawn_position := load_position

	# Wait until the standalone Phase 2/3 collision bodies queued for deletion are gone.
	await get_tree().physics_frame
	$RisingLava.restore_save_state(data)

	if (
		data.has("player_position_x")
		and data.has("player_position_y")
	):
		var saved_position := Vector2(
			data["player_position_x"],
			data["player_position_y"]
		)
		load_position = saved_position

		if _is_valid_dynamic_respawn(saved_position, phase):
			safe_respawn_position = saved_position
		else:
			var nearby_safe := _find_nearby_safe_position(
				saved_position,
				phase
			)

			if not nearby_safe.is_empty():
				safe_respawn_position = nearby_safe["position"]

	player.global_position = load_position
	player.velocity = Vector2.ZERO
	player.set_facing_direction(
		int(data.get("facing_direction", 1))
	)
	last_safe_position = safe_respawn_position
	_reset_safe_candidate()

	# Let the physics server synchronize both restored transforms before checking contact.
	# Otherwise the old spawn position can generate a stale lava overlap and reset the save.
	$RisingLava/StartDelayTimer.paused = true

	var camera: Camera2D = player.get_node("Camera2D")

	camera.reset_smoothing()
	camera.force_update_scroll()

	while get_tree().paused:
		await get_tree().process_frame

	await get_tree().physics_frame
	await get_tree().process_frame

	$RisingLava.monitoring = true
	$RisingLava/StartDelayTimer.paused = false

	player.set_physics_process(true)
	$RisingLava.set_physics_process(true)
	_is_restoring_save = false


func _is_position_clear(target: Vector2) -> bool:
	var collision_shape := (
		player.get_node_or_null("CollisionShape2D")
		as CollisionShape2D
	)

	if collision_shape == null or collision_shape.shape == null:
		return false

	var query := PhysicsShapeQueryParameters2D.new()

	query.shape = collision_shape.shape

	var target_transform := player.global_transform

	# Check one pixel above the requested position so standing floor contact is valid.
	target_transform.origin = target + Vector2.UP

	query.transform = target_transform * collision_shape.transform
	query.collision_mask = player.collision_mask
	query.exclude = [player.get_rid()]
	query.collide_with_bodies = true
	query.collide_with_areas = false

	return (
		get_world_2d()
		.direct_space_state
		.intersect_shape(query, 1)
		.is_empty()
	)


func get_save_checkpoint() -> Dictionary:
	var phase := active_phase
	var checkpoint: Vector2 = checkpoints[phase]

	# Read the live global coordinates on GUARDAR, including while the tree is paused.
	var data := {
		"phase": phase,
		"checkpoint_id": "checkpoint_%02d" % phase,
		"checkpoint_x": checkpoint.x,
		"checkpoint_y": checkpoint.y,
		"player_position_x": player.global_position.x,
		"player_position_y": player.global_position.y,
		"facing_direction": player.get_facing_direction()
	}

	data.merge($RisingLava.get_save_state())

	return data


func _play_fade_in() -> void:
	fade_in.visible = true
	fade_in.color.a = 1.0

	# Esperar un par de frames para garantizar que el negro
	# se dibuje antes de comenzar a desaparecer.
	await get_tree().process_frame
	await get_tree().process_frame

	var tween := create_tween()

	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(
		fade_in,
		"color:a",
		0.0,
		0.75
	)

	await tween.finished

	fade_in.visible = false
