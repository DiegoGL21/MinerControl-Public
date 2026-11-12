extends Control

const OPTIONS_MENU_SCENE := preload("res://scenes/ui/menus/options_menu.tscn")
const OPTIONS_MENU_SETTINGS := preload("res://scripts/ui/options_menu.gd")
const COMPLETED_GAME_TOOLTIP := (
	"Ya completaste este juego. "
	+ "Inicia una nueva partida para volver a jugar."
)

var _options_menu: Control
var _transitioning := false

@onready var fade: ColorRect = $TransitionLayer/Fade


func _ready() -> void:
	OPTIONS_MENU_SETTINGS.apply_saved_settings()

	$MenuMusic.play()

	var save_data := SaveManager.read_save()
	var has_save := not save_data.is_empty()
	var completed := bool(
		save_data.get("level_01_completed", false)
	)
	var continue_button: Button = $MenuButtons/ContinueButton
	continue_button.disabled = not has_save or completed
	continue_button.tooltip_text = (
		COMPLETED_GAME_TOOLTIP
		if has_save and completed
		else ""
	)
	var continue_art := continue_button.get_node_or_null("Art") as CanvasItem
	if continue_art != null:
		continue_art.modulate = (
			Color(0.45, 0.45, 0.45, 0.75)
			if continue_button.disabled
			else Color.WHITE
		)

	$SaveStatus.text = (
		SaveManager.last_error
		if FileAccess.file_exists(SaveManager.save_path)
		else ""
	)

	fade.visible = true
	fade.color.a = 0.0

	_configure_menu_focus()

	for child in $MenuButtons.get_children():
		if child is Button:
			child.mouse_entered.connect(
				_on_menu_button_mouse_entered.bind(child)
			)
			child.mouse_exited.connect(
				_update_menu_button_highlight.bind(child)
			)
			child.focus_entered.connect(
				_update_menu_button_highlight.bind(child)
			)
			child.focus_exited.connect(
				_update_menu_button_highlight.bind(child)
			)
			_update_menu_button_highlight.call_deferred(child)


func _on_menu_button_mouse_entered(button: Button) -> void:
	if not button.disabled:
		button.grab_focus()
	_update_menu_button_highlight.call_deferred(button)


func _update_menu_button_highlight(button: Button) -> void:
	var highlight := button.get_node_or_null("Highlight") as CanvasItem
	if highlight == null:
		return
	highlight.visible = (
		not button.disabled
		and (button.is_hovered() or button.has_focus())
	)


func _configure_menu_focus() -> void:
	var buttons: Array[Button] = [
		$MenuButtons/PlayButton,
		$MenuButtons/SettingsButton,
		$MenuButtons/ExitButton,
	]

	if not $MenuButtons/ContinueButton.disabled:
		buttons.insert(1, $MenuButtons/ContinueButton)

	for index in buttons.size():
		var button := buttons[index]
		var previous := buttons[maxi(index - 1, 0)]
		var next := buttons[mini(index + 1, buttons.size() - 1)]

		button.focus_neighbor_top = button.get_path_to(previous)
		button.focus_neighbor_bottom = button.get_path_to(next)

		button.focus_previous = button.get_path_to(
			buttons[posmod(index - 1, buttons.size())]
		)

		button.focus_next = button.get_path_to(
			buttons[(index + 1) % buttons.size()]
		)


func _on_continue_button_pressed() -> void:
	if _transitioning:
		return

	if not SaveManager.load_game():
		$SaveStatus.text = SaveManager.last_error
		return

	_transitioning = true
	get_tree().paused = false

	await _fade_out()

	var level_id: String = String(
		SaveManager.pending_load.get(
			"level_id",
			LevelRegistry.FIRST_LEVEL_ID
		)
	)
	var error: Error = LevelRegistry.change_to_level(level_id)

	if error != OK:
		SaveManager.pending_load.clear()
		$SaveStatus.text = "No se pudo abrir el nivel."

		_transitioning = false
		await _fade_back()


func _on_play_button_pressed() -> void:
	if _transitioning:
		return

	_transitioning = true

	SaveManager.new_game()
	get_tree().paused = false

	await _fade_out()

	var error := get_tree().change_scene_to_file(
		"res://scenes/intro/intro.tscn"
	)

	if error != OK:
		$SaveStatus.text = "No se pudo abrir la introducción."

		_transitioning = false
		await _fade_back()


func _fade_out() -> void:
	fade.visible = true
	fade.color.a = 0.0

	var tween := create_tween()

	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(
		fade,
		"color:a",
		1.0,
		2.0
	)

	await tween.finished


func _fade_back() -> void:
	var tween := create_tween()

	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(
		fade,
		"color:a",
		0.0,
		2.0
	)

	await tween.finished

	fade.visible = false


func _on_exit_button_pressed() -> void:
	get_tree().quit()


func _on_settings_button_pressed() -> void:
	if is_instance_valid(_options_menu):
		return

	_options_menu = OPTIONS_MENU_SCENE.instantiate()
	add_child(_options_menu)

	_options_menu.tree_exited.connect(
		_on_options_menu_closed
	)


func _on_options_menu_closed() -> void:
	_options_menu = null

	if (
		is_inside_tree()
		and $MenuButtons/SettingsButton.is_inside_tree()
	):
		$MenuButtons/SettingsButton.grab_focus.call_deferred()
		_update_menu_button_highlight.call_deferred(
			$MenuButtons/SettingsButton
		)
