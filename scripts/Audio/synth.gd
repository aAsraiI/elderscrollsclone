class_name Synth
extends RefCounted
## Sounds and music made in code (there are no audio files): short noise bursts, tones and
## sweeps for effects, and slow chord pads for music. Each sound is made once and cached.
## To use real recordings instead, put .wav / .ogg files in res://audio/ with the same names
## (swing.wav, hit.ogg...) and SoundFX plays those.

const RATE := 22050
const MUSIC_RATE := 11025

static var _cache := {}


static func get_sound(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	for ext in [".ogg", ".wav", ".mp3"]:
		var path: String = "res://audio/" + name + ext
		if ResourceLoader.exists(path):
			_cache[name] = load(path)
			return _cache[name]
	var s := _make(name)
	_cache[name] = s
	return s


static func _make(name: String) -> AudioStreamWAV:
	match name:
		"swing":
			return _noise(0.2, 0.25, 0.02, 3.0, 0.6)
		"swing_heavy":
			return _noise(0.32, 0.18, 0.06, 2.0, 0.7)
		"hit":
			return _mix([_tone(0.16, 85.0, 0.0, 14.0, 0.9), _noise(0.08, 0.5, 0.0, 30.0, 0.5)])
		"block":
			return _mix([_tone(0.35, 820.0, 0.0, 9.0, 0.25), _tone(0.35, 1230.0, 0.0, 11.0, 0.2), _tone(0.35, 1910.0, 0.0, 13.0, 0.15), _noise(0.05, 0.9, 0.0, 40.0, 0.3)])
		"hurt":
			return _mix([_tone(0.2, 140.0, 0.0, 10.0, 0.7), _noise(0.12, 0.3, 0.0, 18.0, 0.4)])
		"cast":
			return _mix([_sweep(0.4, 260.0, 900.0, 0.5), _noise(0.4, 0.4, 0.05, 5.0, 0.3)])
		"boom":
			return _noise(0.8, 0.08, 0.0, 4.0, 1.0)
		"step":
			return _noise(0.07, 0.12, 0.0, 35.0, 0.35)
		"twang":
			return _mix([_tone(0.3, 196.0, 0.0, 12.0, 0.6), _tone(0.3, 392.0, 0.0, 16.0, 0.25), _noise(0.05, 0.7, 0.0, 50.0, 0.3)])
		"click":
			return _tone(0.04, 1300.0, 0.0, 60.0, 0.3)
		"pickup":
			return _mix([_tone(0.08, 660.0, 0.0, 25.0, 0.3), _tone(0.16, 990.0, 0.06, 20.0, 0.3)])
		"thunder":
			return _noise(2.6, 0.04, 0.05, 1.3, 1.0)
		"rain":
			return _noise(2.0, 0.6, 0.0, 0.0, 0.25, true)
		"wind":
			return _noise(3.0, 0.03, 0.0, 0.0, 0.3, true)
		"level_up":
			return _mix([_tone(0.6, 523.0, 0.0, 3.0, 0.3), _tone(0.6, 659.0, 0.1, 3.0, 0.3), _tone(0.7, 784.0, 0.2, 3.0, 0.3)])
	return _tone(0.05, 440.0, 0.0, 30.0, 0.1)


# ---------------------------------------------------------------- building blocks

static func _wav(data: PackedFloat32Array, rate: int = RATE, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = data.size()
	return w


## White noise through a one-pole low-pass (smooth 0..1: lower = darker), with attack and decay
static func _noise(dur: float, smooth: float, attack: float, decay: float, vol: float, loop: bool = false) -> AudioStreamWAV:
	return _wav(_noise_data(dur, smooth, attack, decay, vol), RATE, loop)


static func _noise_data(dur: float, smooth: float, attack: float, decay: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(dur * 1000.0 + smooth * 77.0)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		y += (rng.randf_range(-1.0, 1.0) - y) * smooth
		var env := minf(t / attack, 1.0) if attack > 0.0 else 1.0
		if decay > 0.0:
			env *= exp(-t * decay)
		out[i] = y * env * vol * (1.0 / maxf(sqrt(smooth), 0.2))
	return out


static func _tone(dur: float, freq: float, delay: float, decay: float, vol: float) -> AudioStreamWAV:
	return _wav(_tone_data(dur, freq, delay, decay, vol))


static func _tone_data(dur: float, freq: float, delay: float, decay: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE - delay
		if t < 0.0:
			continue
		out[i] = sin(TAU * freq * t) * exp(-t * decay) * vol * minf(t * 400.0, 1.0)
	return out


static func _sweep(dur: float, f0: float, f1: float, vol: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		phase += TAU * lerpf(f0, f1, t) / RATE
		out[i] = sin(phase) * sin(t * PI) * vol
	return _wav(out)


static func _mix(parts: Array) -> AudioStreamWAV:
	var n := 0
	var datas: Array[PackedFloat32Array] = []
	for p in parts:
		var w := p as AudioStreamWAV
		var d := PackedFloat32Array()
		d.resize(w.data.size() / 2)
		for i in d.size():
			d[i] = float(w.data.decode_s16(i * 2)) / 32000.0
		datas.append(d)
		n = maxi(n, d.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for d in datas:
		for i in d.size():
			out[i] += d[i]
	return _wav(out)


# ---------------------------------------------------------------- music

## A slow looping pad for a mood: "day", "night", "dungeon", "combat". Takes a moment to make:
## call it from a worker thread (SoundFX does).
static func make_music(mood: String) -> AudioStreamWAV:
	var chords: Array = []
	var beat := 3.0
	match mood:
		"day":
			chords = [[261.6, 329.6, 392.0], [349.2, 440.0, 523.3], [392.0, 493.9, 587.3], [220.0, 261.6, 329.6]]
		"night":
			chords = [[220.0, 261.6, 329.6], [146.8, 174.6, 220.0], [164.8, 196.0, 246.9], [220.0, 261.6, 329.6]]
			beat = 4.0
		"dungeon":
			chords = [[110.0, 164.8, 207.7], [103.8, 155.6, 196.0], [110.0, 164.8, 196.0], [98.0, 146.8, 185.0]]
			beat = 4.0
		_:
			chords = [[110.0, 130.8, 164.8], [98.0, 116.5, 146.8], [87.3, 110.0, 130.8], [98.0, 123.5, 146.8]]
			beat = 1.5
	var n := int(beat * chords.size() * MUSIC_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var per := int(beat * MUSIC_RATE)
	for c in chords.size():
		var notes: Array = chords[c]
		for i in per:
			var t := float(i) / MUSIC_RATE
			var env := minf(t / (beat * 0.35), 1.0) * minf((beat - t) / (beat * 0.35), 1.0)
			var v := 0.0
			for f in notes:
				v += sin(TAU * float(f) * t) * 0.5 + sin(TAU * float(f) * 2.0 * t) * 0.12 + sin(TAU * float(f) * 0.5 * t) * 0.2
			if mood == "combat":
				v += sin(TAU * float(notes[0]) * 0.5 * t) * 0.9 * exp(-fmod(t, beat / 4.0) * 9.0)
			out[c * per + i] = v * env * 0.16
	return _wav(out, MUSIC_RATE, true)
