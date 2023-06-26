# Godot Synth

A simple synthesizer in GDScript for Godot 4.

It exists as a demonstration of how to generate sound in realtime in Godot.

Based on the
[Godot 3.5 Audio Generator Demo](https://github.com/godotengine/godot-demo-projects/tree/3.5-9e68af3/audio/generator).

<a href="media/screenshot-1.png?raw=true"><img width=900 src="media/screenshot-1.png"></a>

## Usage

Add `synth.gd` to your scene. Call `start()` and tweak the synth parameters.

If the dsp cannot keep up and the audio streams stops, you can improve performance by increasing
the `buffer_size` or `buffer_sizes_in_advance` values, or decreasing the `sample_rate`.

Performance is an issue, and the
[Godot docs](https://docs.godotengine.org/en/stable/classes/class_audiostreamgenerator.html#description)
also mention that GDScrpit isn't ideal for this type of work. Compiled languages might work better.

## Demo

Run the `demo/gui.tscn` scene.
