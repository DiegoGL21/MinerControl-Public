extends Control

const MAIN_MENU := "res://scenes/ui/menus/main_menu.tscn"
const SPLASH_VIDEO := "res://assets/video/splash/studline_splash.ogv"
const FALLBACK_TIMEOUT := 12.0
const FADE_DURATION := 0.5
const RETRY_DELAY := 1.0

@onready var _video: VideoStreamPlayer = $VideoAspect/VideoStreamPlayer
@onready var _fade: ColorRect = $Fade

var _transitioning := false


func _ready() -> void:
	_video.finished.connect(_on_video_finished)

	var stream := ResourceLoader.load(SPLASH_VIDEO) as VideoStream

	if stream == null:
		push_error("TeamSplash: no se pudo cargar el video del splash.")
		_begin_transition.call_deferred()
		return

	_video.stream = stream
	_video.play()
	_watch_for_timeout()


func _on_video_finished() -> void:
	_begin_transition()


func _watch_for_timeout() -> void:
	await get_tree().create_timer(FALLBACK_TIMEOUT).timeout

	if not _transitioning:
		push_warning("TeamSplash: el video no finalizo; se activo el fallback.")
		_begin_transition()


func _begin_transition() -> void:
	if _transitioning:
		return

	_transitioning = true
	_video.stop()

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_fade, "color:a", 1.0, FADE_DURATION)

	await tween.finished

	var error := get_tree().change_scene_to_file(MAIN_MENU)

	if error == OK:
		return

	push_error(
		"TeamSplash: no se pudo abrir el menu principal: %s"
		% error_string(error)
	)
	_transitioning = false
	_fade.color.a = 0.0
	await get_tree().create_timer(RETRY_DELAY).timeout
	_begin_transition()
