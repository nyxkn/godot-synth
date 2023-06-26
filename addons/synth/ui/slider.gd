extends HBoxContainer


signal value_changed

@export var range_min_max: Vector2 = Vector2(0, 1)
@export var range_step: float = 1
@export var default_value: float = 0
@export var exponential: bool = false

var value
var _synth


func setup(synth):
	_synth = synth

#	$Label.text = label
	$Label.text = name
	$HSlider.min_value = range_min_max.x
	$HSlider.max_value = range_min_max.y
	$SpinBox.min_value = range_min_max.x
	$SpinBox.max_value = range_min_max.y

	$HSlider.step = range_step
	$SpinBox.step = range_step

	$HSlider.exp_edit = exponential
	$SpinBox.exp_edit = exponential

	value = default_value
	$HSlider.value = value
	$SpinBox.value = value

	value_changed.connect(_synth.set_property.bind(name.to_lower()))
	set_value(value)


func set_value(new_value: float):
	value = new_value
	$Value.text = str(new_value)
	value_changed.emit(new_value)


func _on_h_slider_value_changed(new_value: float) -> void:
	set_value(new_value)
	$SpinBox.set_value_no_signal(new_value)


func _on_spin_box_value_changed(new_value: float) -> void:
	set_value(new_value)
	$HSlider.set_value_no_signal(new_value)
