extends "res://scripts/endings/ending_screen.gd"


@onready var _ending_video: VideoStreamPlayer = $EndingVideo
@onready var _continue_label: Label = $ContinueLabel


var _ending_complete: bool = false


func _ready() -> void:
	_continue_label.visible = false
	_ending_video.finished.connect(_on_ending_video_finished)
	super._ready()


func _unhandled_input(event: InputEvent) -> void:
	if not _ending_complete:
		return

	super._unhandled_input(event)


func play_ending_sequence() -> void:
	_ending_complete = false
	_continue_label.visible = false
	_ending_video.play()


func _on_ending_video_finished() -> void:
	_ending_complete = true
	_continue_label.visible = true
