extends Control

@onready var video: VideoStreamPlayer = $VideoStreamPlayer
@onready var fade: ColorRect = $Fade

var transitioning := false


func _ready() -> void:
	video.finished.connect(_on_video_finished)


func _unhandled_input(event: InputEvent) -> void:
	if transitioning:
		return

	if event.is_action_pressed("ui_accept"):
		_skip_intro()


func _skip_intro() -> void:
	if transitioning:
		return

	transitioning = true
	await _fade_out()
	_continue_to_level_1()


func _on_video_finished() -> void:
	if transitioning:
		return

	transitioning = true

	var tween := create_tween()
	tween.tween_property(
		fade,
		"color:a",
		1.0,
		0.20
	)

	await tween.finished

	var error: Error = LevelRegistry.change_to_level(
		LevelRegistry.FIRST_LEVEL_ID
	)

	if error != OK:
		push_error(
			"No se pudo abrir el primer nivel: "
			+ error_string(error)
		)


func _fade_out() -> void:
	var tween := create_tween()

	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(
		fade,
		"color:a",
		1.0,
		0.75
	)

	await tween.finished


func _continue_to_level_1() -> void:
	var error: Error = LevelRegistry.change_to_level(
		LevelRegistry.FIRST_LEVEL_ID
	)

	if error != OK:
		push_error(
			"No se pudo abrir el primer nivel: "
			+ error_string(error)
		)
