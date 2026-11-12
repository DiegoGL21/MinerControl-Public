extends CanvasLayer

var _restarting := false

@onready var _reappear_button: Button = $Overlay/ReappearButton
@onready var _button_animation: AnimatedSprite2D = $Overlay/ReappearAnimation
@onready var _game_over_sfx: AudioStreamPlayer = $GameOverSfx


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_reappear_button.pressed.connect(_on_reappear_pressed)
	_reappear_button.mouse_entered.connect(_on_button_mouse_entered)
	_reappear_button.mouse_exited.connect(_on_button_mouse_exited)
	visible = false


func show_game_over() -> void:
	_restarting = false
	visible = true
	_game_over_sfx.play()
	_button_animation.stop()
	_button_animation.frame = 0
	get_tree().paused = true
	_reappear_button.grab_focus()


func _on_button_mouse_entered() -> void:
	if visible and not _restarting:
		_button_animation.play(&"hover")


func _on_button_mouse_exited() -> void:
	_button_animation.stop()
	_button_animation.frame = 0


func _on_reappear_pressed() -> void:
	if _restarting:
		return
	_restarting = true
	_reappear_button.disabled = true
	SaveManager.new_game()
	get_tree().paused = false
	var error := get_tree().reload_current_scene()
	if error != OK:
		_restarting = false
		_reappear_button.disabled = false
		get_tree().paused = true
		push_error("GameOver: no se pudo reiniciar Level01: %s" % error_string(error))
