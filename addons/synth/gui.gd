extends Control


const Synth = preload("res://addons/synth/synth.gd")

var _synth = null


func _init() -> void:
	_synth = Synth.new()


func _ready() -> void:
	add_child(_synth)

	%Pitch.range_min_max = _synth.pitch_range
	%Pitch.range_step = 0.1
	%Pitch.default_value = 440

	%Waveform.range_min_max = Vector2(0, 3)

	%Volume.default_value = 0.5
	%Volume.range_step = 0.01

	%Cutoff.range_min_max = Vector2(
		_synth.pitch_range.x,
		_synth.sample_rate / 2.0 - (_synth.sample_rate / 100.0))
	%Cutoff.default_value = 5000
	%Cutoff.range_step = 1

	%Width.range_step = 0.01
	%Width.default_value = 0.5

	%Resonance.range_min_max = Vector2(0.1, 100)
	%Resonance.range_step = 0.1
	%Resonance.default_value = 1
	%Resonance.exponential = true


	for child in $VBoxContainer.get_children():
		if child is HBoxContainer:
			child.setup(_synth)

	_synth.start()



