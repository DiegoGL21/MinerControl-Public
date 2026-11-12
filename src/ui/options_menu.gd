extends Control

const SETTINGS_PATH := "user://settings.cfg"
const MUSIC_BUS := &"Music"
const EFFECTS_BUS := &"SFX"
const DEFAULT_MUSIC_VOLUME := 70.0
const DEFAULT_EFFECTS_VOLUME := 80.0
const MIN_VOLUME := 0.0
const MAX_VOLUME := 100.0
const WINDOWED_SIZE := Vector2i(1280, 720)

static var _issued_warnings: Dictionary = {}

@onready var music_slider: HSlider = $PanelContainer/MarginContainer/Content/MusicSection/MusicRow/MusicSlider
@onready var music_value: Label = $PanelContainer/MarginContainer/Content/MusicSection/MusicRow/MusicValue
@onready var effects_slider: HSlider = $PanelContainer/MarginContainer/Content/EffectsSection/EffectsRow/EffectsSlider
@onready var effects_value: Label = $PanelContainer/MarginContainer/Content/EffectsSection/EffectsRow/EffectsValue
@onready var fullscreen_button: CheckButton = $PanelContainer/MarginContainer/Content/FullscreenRow/FullscreenButton
@onready var back_button: Button = $PanelContainer/MarginContainer/Content/BackCenter/BackButton
@onready var back_highlight: Panel = $PanelContainer/MarginContainer/Content/BackCenter/BackButton/Highlight

var _syncing_controls := false


func _ready() -> void:
	var settings := apply_saved_settings()
	_syncing_controls = true
	music_slider.value = settings.music_volume
	effects_slider.value = settings.effects_volume
	fullscreen_button.button_pressed = _is_fullscreen()
	_update_percentage(music_value, music_slider.value)
	_update_percentage(effects_value, effects_slider.value)
	_update_fullscreen_text()
	_syncing_controls = false
	_configure_focus()
	back_button.mouse_entered.connect(_update_back_highlight)
	back_button.mouse_exited.connect(_update_back_highlight)
	back_button.focus_entered.connect(_update_back_highlight)
	back_button.focus_exited.connect(_update_back_highlight)
	_update_back_highlight.call_deferred()
	music_slider.grab_focus()


static func apply_saved_settings() -> Dictionary:
	var settings := _load_settings()
	_apply_bus_volume(MUSIC_BUS, settings.music_volume)
	_apply_bus_volume(EFFECTS_BUS, settings.effects_volume)
	_apply_window_mode(settings.fullscreen)
	settings.fullscreen = _is_fullscreen()
	return settings


static func _load_settings() -> Dictionary:
	var settings := {
		"music_volume": DEFAULT_MUSIC_VOLUME,
		"effects_volume": DEFAULT_EFFECTS_VOLUME,
		"fullscreen": _is_fullscreen(),
	}
	if not FileAccess.file_exists(SETTINGS_PATH):
		return settings
	var config := ConfigFile.new()
	var load_error := config.load(SETTINGS_PATH)
	if load_error != OK:
		_warn_once(&"settings_load", "OptionsMenu: settings.cfg no se pudo cargar; se usaran valores predeterminados (%s)." % error_string(load_error))
		return settings
	settings.music_volume = _read_volume_setting(config, &"music_volume", DEFAULT_MUSIC_VOLUME)
	settings.effects_volume = _read_volume_setting(config, &"effects_volume", DEFAULT_EFFECTS_VOLUME)
	settings.fullscreen = _read_bool_setting(config, &"fullscreen", settings.fullscreen)
	return settings


static func _read_volume_setting(config: ConfigFile, key: StringName, default_value: float) -> float:
	var value: Variant = config.get_value("audio", key, default_value)
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		_warn_once(StringName("invalid_%s_type" % key), "OptionsMenu: %s debe ser numerico; se usara %.0f." % [key, default_value])
		return default_value
	var numeric_value := float(value)
	var clamped_value := clampf(numeric_value, MIN_VOLUME, MAX_VOLUME)
	if not is_equal_approx(numeric_value, clamped_value):
		_warn_once(StringName("invalid_%s_range" % key), "OptionsMenu: %s esta fuera de 0-100 y se limitara al rango valido." % key)
	return clamped_value


static func _read_bool_setting(config: ConfigFile, key: StringName, default_value: bool) -> bool:
	var value: Variant = config.get_value("video", key, default_value)
	if typeof(value) != TYPE_BOOL:
		_warn_once(StringName("invalid_%s_type" % key), "OptionsMenu: %s debe ser booleano; se usara el estado actual de la ventana." % key)
		return default_value
	return value


static func _apply_bus_volume(bus_name: StringName, value: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		_warn_once(StringName("missing_bus_%s" % bus_name), "OptionsMenu: no se encontro el bus de audio %s." % bus_name)
		return
	var normalized := clampf(value, MIN_VOLUME, MAX_VOLUME) / MAX_VOLUME
	if is_zero_approx(normalized):
		AudioServer.set_bus_mute(bus_index, true)
		return
	AudioServer.set_bus_mute(bus_index, false)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(normalized))


static func _warn_once(key: StringName, message: String) -> void:
	if _issued_warnings.has(key):
		return
	_issued_warnings[key] = true
	push_warning(message)


static func _is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]


static func _apply_window_mode(fullscreen: bool) -> void:
	var target_mode := (
		DisplayServer.WINDOW_MODE_FULLSCREEN
		if fullscreen
		else DisplayServer.WINDOW_MODE_WINDOWED
	)
	if DisplayServer.window_get_mode() != target_mode:
		DisplayServer.window_set_mode(target_mode)
	if not fullscreen:
		DisplayServer.window_set_size(WINDOWED_SIZE)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "music_volume", clampf(music_slider.value, MIN_VOLUME, MAX_VOLUME))
	config.set_value("audio", "effects_volume", clampf(effects_slider.value, MIN_VOLUME, MAX_VOLUME))
	config.set_value("video", "fullscreen", _is_fullscreen())
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("OptionsMenu: no se pudieron guardar las opciones: %s" % error_string(error))


func _on_music_value_changed(value: float) -> void:
	var safe_value := clampf(value, MIN_VOLUME, MAX_VOLUME)
	_update_percentage(music_value, safe_value)
	_apply_bus_volume(MUSIC_BUS, safe_value)
	if not _syncing_controls:
		_save_settings()


func _on_effects_value_changed(value: float) -> void:
	var safe_value := clampf(value, MIN_VOLUME, MAX_VOLUME)
	_update_percentage(effects_value, safe_value)
	_apply_bus_volume(EFFECTS_BUS, safe_value)
	if not _syncing_controls:
		_save_settings()


func _on_fullscreen_toggled(toggled_on: bool) -> void:
	if _syncing_controls:
		return
	_apply_window_mode(toggled_on)
	var actual_fullscreen := _is_fullscreen()
	fullscreen_button.set_pressed_no_signal(actual_fullscreen)
	_update_fullscreen_text()
	if actual_fullscreen != toggled_on:
		_warn_once(&"fullscreen_rejected", "OptionsMenu: el sistema no pudo aplicar el modo de pantalla solicitado.")
	_save_settings()


func _on_back_pressed() -> void:
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_WINDOW_FOCUS_IN or not is_node_ready():
		return
	_syncing_controls = true
	fullscreen_button.button_pressed = _is_fullscreen()
	_update_fullscreen_text()
	_syncing_controls = false


func _update_percentage(label: Label, value: float) -> void:
	label.text = "%d %%" % roundi(value)


func _update_fullscreen_text() -> void:
	fullscreen_button.text = ""


func _update_back_highlight() -> void:
	back_highlight.visible = (
		back_button.is_hovered()
		or back_button.has_focus()
	)


func _configure_focus() -> void:
	music_slider.focus_neighbor_bottom = music_slider.get_path_to(effects_slider)
	effects_slider.focus_neighbor_top = effects_slider.get_path_to(music_slider)
	effects_slider.focus_neighbor_bottom = effects_slider.get_path_to(fullscreen_button)
	fullscreen_button.focus_neighbor_top = fullscreen_button.get_path_to(effects_slider)
	fullscreen_button.focus_neighbor_bottom = fullscreen_button.get_path_to(back_button)
	back_button.focus_neighbor_top = back_button.get_path_to(fullscreen_button)
