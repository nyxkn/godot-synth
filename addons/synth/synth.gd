extends Node


signal wave_cycle_completed(waveform)

const pitch_range := Vector2(16.35160, 2093.005)

# sample rate is also the number of audio frames per second
const sample_rate: float = 44100
#var sample_rate = 22050.0 # Keep the number of samples to mix low, GDScript is not super fast.
#var sample_rate: float = 11025
#var inv_sample_rate: float = 1.0 / sample_rate

# buffer size for dsp computation
const buffer_size: float = 512
# multiples of the buffer size that we let the audio generator create in advance
# the higher this is, the greater the latency
const buffer_sizes_in_advance: int = 2

enum FillMode { FRAME, CHUNK }
const fill_mode = FillMode.CHUNK

var audio_stream_generator: AudioStreamGeneratorPlayback = null
var audio_stream_player: AudioStreamPlayer = null

# phase is the current position within the wavecycle
# it goes from 0 to 1. it's the x axis, but only for one cycle
var _phase: float = 0.0
var _start_latency
var _start_latency_full
var _waveform_data: PackedVector2Array = []
var _last_waveform_data: PackedVector2Array = []
var _frames_available: int = 0

var playing = false
var pitch: float = 440
var waveform: int = 0
var width: float = 0.5
var volume: float = 1 :
	set(v):
		volume = v
		audio_stream_player.volume_db = linear_to_db(volume)
var cutoff: float = 5000 :
	set(v):
		cutoff = clamp(v, 1, sample_rate / 2.0 - (sample_rate / 100.0))
var filter: int = 0
var resonance: float = 1.0


var _thread: Thread

func _ready():
	_thread = Thread.new()

	audio_stream_player = AudioStreamPlayer.new()
	add_child(audio_stream_player)
	audio_stream_player.stream = AudioStreamGenerator.new()
	audio_stream_player.stream.mix_rate = sample_rate
	# how many seconds to buffer ahead. we want to keep this as low as possible to avoid latency
	# length of buffer_size * 2 because less doesn't seem to keep up
	audio_stream_player.stream.buffer_length = (buffer_size) / sample_rate * buffer_sizes_in_advance
	print(str("buffer length: ", audio_stream_player.stream.buffer_length))


func start():
	audio_stream_player.play()
	audio_stream_player.stream_paused = true
	audio_stream_player.seek(0.0)

#	await get_tree().process_frame # needed?

	audio_stream_generator = audio_stream_player.get_stream_playback()
	# prefill, do before play() to avoid delay.
	# actually that doesn't work. play() needs to be called first to be able to get stream playback
	print(str("frames available: ", audio_stream_generator.get_frames_available()))
	fill_buffer(true)

	playing = true
	_thread.start(thread_loop, Thread.PRIORITY_NORMAL)


func thread_loop():
	_phase = 0.0
	_start_latency = AudioServer.get_output_latency()
	_start_latency_full = AudioServer.get_time_to_next_mix() + _start_latency
	audio_stream_player.stream_paused = false

	var last_time = Time.get_ticks_usec()

	print("thread start")

	while playing:
		if not audio_stream_player.playing:
			if _frames_available == 0:
				print("stream stopped. audio generator could not provide frames fast enough")
			else:
				print(str("stream stopped. we couldn't fill frames fast enough. frames available:", _frames_available))
			playing = false
			return

		var delta = (Time.get_ticks_usec() - last_time) * pow(0.1, 6)
#		print(delta)

		fill_buffer()

		last_time = Time.get_ticks_usec()
#		OS.delay_usec(1)
		OS.delay_msec(1)

	print("thread end")

	return "thread loop finished"


func stop():
	playing = false
	print_debug(_thread.wait_to_finish())


# swapping params. property last because bind() works from right to left
func set_property(value, property):
	set(property, value)


func fill_buffer(prefill = false):
	_frames_available = audio_stream_generator.get_frames_available()
	print(_frames_available)

	# when we use fill by frame, we process single frames as soon as they are available
	# in chunk mode, we wait unti there's a big enough chunk
	# frames become available in chunks anyway, seemingly 512 or 1024
	# we are using (buffer_size -1) in chunk mode because audiogenerator seems to often generate buffer_size-1 frames. e.g. 255, 511
	if (fill_mode == FillMode.FRAME and _frames_available > 0) or (fill_mode == FillMode.CHUNK and _frames_available >= buffer_size -1):
		var to_fill
		if prefill:
			to_fill = _frames_available
		else:
			to_fill = min(_frames_available, buffer_size)

		var buffer: PackedVector2Array = []
		while to_fill > 0:
			var sample = generate_waveform_sample(_phase)

			if filter == 1:
				sample = biquad(sample)

			# audio frames we send to audioplayer need to be stereo: vector2(left, right)
			var sample_stereo = sample * Vector2.ONE

			if fill_mode == FillMode.CHUNK:
				buffer.append(sample_stereo)
			else:
				audio_stream_generator.push_frame(sample_stereo)

			to_fill -= 1
			var increment = pitch / sample_rate
			var new_phase = fmod(_phase + increment, 1.0)
			if new_phase < _phase:
				_last_waveform_data = _waveform_data.duplicate()
				_waveform_data.clear()
				call_deferred("emit_signal", "wave_cycle_completed", _last_waveform_data)
			else:
				_waveform_data.append(Vector2(_phase, sample))
			_phase = new_phase

		if fill_mode == FillMode.CHUNK:
			audio_stream_generator.push_buffer(buffer)



func sine(x):
	return sin(x * TAU)

func pulse(x, width):
	return int(x > width) * 2 - 1

func saw(x):
	return (1 - x) * 2 - 1

func triangle(x):
	return abs(x * 2 - 1) * 2 - 1

func generate_waveform_sample(phase):
	var y
	match waveform:
		0: y = saw(_phase)
		1: y = pulse(_phase, width)
		2: y = triangle(_phase)
		3: y = sine(_phase)
	# we might want to do volume adjustment with audioplayer volume instead of on the waveform
	# y *= volume

	return y


## ================================
## moving average
## this is technically a lowpass filter
## it's good for noise reduction, but not as a lowpass for a synth

var moving_average_window := []  # List to store the values in the window
var moving_average_sum := 0.0  # Current sum of values in the window
#
func moving_average_next(value: float) -> float:
	# Add the new value to the window
	moving_average_window.append(value)
	moving_average_sum += value

	var window_size := 10  # Number of values to consider for the moving average

	# If the window size exceeds the defined size, remove the oldest value
	while moving_average_window.size() > window_size:
		var oldest_value = moving_average_window.pop_front()
		moving_average_sum -= oldest_value

	# Return the moving average
	return moving_average_sum / moving_average_window.size()


## ================================
## biquad filter
## from somewhere on the internet
## only tested lowpass

enum FilterType {
	LOWPASS,
	HIGHPASS,
	BANDPASS,
	NOTCH,
	PEAK,
	LOWSHELF,
	HIGHSHELF
}
var filter_type = FilterType.LOWPASS

var x1 = 0.0
var x2 = 0.0
var y1 = 0.0
var y2 = 0.0

func biquad(input, filter_type: FilterType = FilterType.LOWPASS):
	var inv_sample_rate: float = 1.0 / sample_rate

	var frequency = cutoff * inv_sample_rate
#	var q = 1.0 / (2.0 * resonance)
	var q = resonance

	var omega = TAU * frequency
	var sin_omega = sin(omega)
	var cos_omega = cos(omega)
	var alpha = sin_omega / (2.0 * q)

	var a0 = 0.0
	var a1 = 0.0
	var a2 = 0.0
	var b0 = 0.0
	var b1 = 0.0
	var b2 = 0.0

	var norm = 0.0

	match filter_type:
		FilterType.LOWPASS:
			b0 = (1.0 - cos_omega) / 2.0
			b1 = 1.0 - cos_omega
			b2 = (1.0 - cos_omega) / 2.0
			a0 = 1.0 + alpha
			a1 = -2.0 * cos_omega
			a2 = 1.0 - alpha
		FilterType.HIGHPASS:
			b0 = (1.0 + cos_omega) / 2.0
			b1 = -(1.0 + cos_omega)
			b2 = (1.0 + cos_omega) / 2.0
			a0 = 1.0 + alpha
			a1 = -2.0 * cos_omega
			a2 = 1.0 - alpha
		FilterType.BANDPASS:
			b0 = alpha
			b1 = 0.0
			b2 = -alpha
			a0 = 1.0 + alpha
			a1 = -2.0 * cos_omega
			a2 = 1.0 - alpha
		FilterType.NOTCH:
			b0 = 1.0
			b1 = -2.0 * cos_omega
			b2 = 1.0
			a0 = 1.0 + alpha
			a1 = -2.0 * cos_omega
			a2 = 1.0 - alpha
		FilterType.PEAK:
			b0 = 1.0 + alpha * resonance
			b1 = -2.0 * cos_omega
			b2 = 1.0 - alpha * resonance
			a0 = 1.0 + alpha / resonance
			a1 = -2.0 * cos_omega
			a2 = 1.0 - alpha / resonance
		FilterType.LOWSHELF:
			b0 = (resonance + 1.0) + (resonance - 1.0) * cos_omega + 2.0 * sqrt(resonance) * alpha
			b1 = -2.0 * ((resonance - 1.0) + (resonance + 1.0) * cos_omega)
			b2 = (resonance + 1.0) + (resonance - 1.0) * cos_omega - 2.0 * sqrt(resonance) * alpha
			a0 = (resonance + 1.0) - (resonance - 1.0) * cos_omega + 2.0 * sqrt(resonance) * alpha
			a1 = 2.0 * ((resonance - 1.0) - (resonance + 1.0) * cos_omega)
			a2 = (resonance + 1.0) - (resonance - 1.0) * cos_omega - 2.0 * sqrt(resonance) * alpha
		FilterType.HIGHSHELF:
			b0 = (resonance + 1.0) - (resonance - 1.0) * cos_omega + 2.0 * sqrt(resonance) * alpha
			b1 = 2.0 * ((resonance - 1.0) - (resonance + 1.0) * cos_omega)
			b2 = (resonance + 1.0) - (resonance - 1.0) * cos_omega - 2.0 * sqrt(resonance) * alpha
			a0 = (resonance + 1.0) + (resonance - 1.0) * cos_omega + 2.0 * sqrt(resonance) * alpha
			a1 = -2.0 * ((resonance - 1.0) + (resonance + 1.0) * cos_omega)
			a2 = (resonance + 1.0) + (resonance - 1.0) * cos_omega - 2.0 * sqrt(resonance) * alpha

	norm = 1.0 / a0

	var output = norm * (b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2)

	x2 = x1
	x1 = input
	y2 = y1
	y1 = output

	return output
