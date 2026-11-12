extends Control


const MAIN_MENU_SCENE: String = (
	"res://scenes/ui/menus/main_menu.tscn"
)

const FADE_DURATION: float = 0.65


var _ready_for_continue: bool = false
var _transitioning: bool = false


@onready var _fade: ColorRect = $Fade


func _ready() -> void:
	get_tree().paused = false
	_update_mineral_label()
	_play_fade_in()


func _unhandled_input(event: InputEvent) -> void:
	if (
		_ready_for_continue
		and not _transitioning
		and event.is_action_pressed(&"ui_accept")
	):
		_transitioning = true
		get_viewport().set_input_as_handled()
		_return_to_menu()


func _update_mineral_label() -> void:
	var minerals_label: Label = _get_minerals_label()

	if minerals_label == null:
		return

	minerals_label.text = "Minerales: %d / %d" % [
		SaveManager.get_collected_mineral_count(),
		SaveManager.total_minerals
	]


func _get_minerals_label() -> Label:
	var normal_label: Label = get_node_or_null(
		"Content/Minerals"
	) as Label

	if normal_label != null:
		return normal_label

	return get_node_or_null(
		"UILayer/Content/MineralsLabel"
	) as Label


func _play_fade_in() -> void:
	_fade.visible = true
	_fade.color.a = 1.0

	await get_tree().process_frame
	await get_tree().process_frame

	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(
		_fade,
		"color:a",
		0.0,
		FADE_DURATION
	)

	await tween.finished

	_fade.visible = false
	_ready_for_continue = true


func _return_to_menu() -> void:
	_fade.visible = true

	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(
		_fade,
		"color:a",
		1.0,
		FADE_DURATION
	)

	await tween.finished

	var error: Error = get_tree().change_scene_to_file(
		MAIN_MENU_SCENE
	)

	if error != OK:
		push_error(
			"No se pudo volver al menú principal: "
			+ error_string(error)
		)
		_transitioning = false
		_play_fade_in()
