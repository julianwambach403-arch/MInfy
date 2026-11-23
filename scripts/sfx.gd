extends RefCounted
## Alle Soundeffekte werden beim Start synthetisiert (keine Audiodateien nötig).

const RATE := 22050


static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


static func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


static func _swing(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(0.22)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / b.size()
		var cut := 0.05 + 0.25 * sin(t * PI)
		lp += (rng.randf_range(-1, 1) - lp) * cut
		b[i] = lp * sin(t * PI) * 1.6
	return b


static func _hit(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(0.18)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := lerpf(140.0, 55.0, t / 0.18)
		ph += TAU * f / RATE
		var env := exp(-t * 22.0)
		b[i] = (sin(ph) * 0.8 + rng.randf_range(-1, 1) * 0.5 * exp(-t * 60.0)) * env
	return b


static func _hurt() -> PackedFloat32Array:
	var b := _buf(0.25)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += TAU * lerpf(220.0, 90.0, t / 0.25) / RATE
		b[i] = (1.0 if sin(ph) > 0.0 else -1.0) * 0.35 * exp(-t * 10.0)
	return b


static func _cast(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(0.4)
	var ph := 0.0
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += TAU * lerpf(250.0, 900.0, t / 0.4) / RATE
		lp += (rng.randf_range(-1, 1) - lp) * 0.2
		b[i] = (sin(ph) * 0.4 + lp * 0.6) * sin(t / 0.4 * PI)
	return b


static func _explode(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(0.7)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (rng.randf_range(-1, 1) - lp) * lerpf(0.4, 0.03, t / 0.7)
		b[i] = lp * 2.2 * exp(-t * 5.0)
	return b


static func _notes(freqs: Array, each: float, vol: float) -> PackedFloat32Array:
	var b := _buf(each * freqs.size() + 0.3)
	for n in freqs.size():
		var start := int(n * each * RATE)
		var f: float = freqs[n]
		for i in int((each + 0.3) * RATE):
			if start + i >= b.size():
				break
			var t := float(i) / RATE
			b[start + i] += (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * vol * exp(-t * 6.0)
	return b


static func _die(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(0.4)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += TAU * lerpf(500.0, 80.0, t / 0.4) / RATE
		b[i] = (sin(ph) * 0.5 + rng.randf_range(-1, 1) * 0.2) * exp(-t * 6.0)
	return b


static func build_all() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	return {
		"swing": _wav(_swing(rng)),
		"hit": _wav(_hit(rng)),
		"hurt": _wav(_hurt()),
		"cast": _wav(_cast(rng)),
		"explode": _wav(_explode(rng)),
		"levelup": _wav(_notes([523.0, 659.0, 784.0, 1046.0], 0.11, 0.3)),
		"coin": _wav(_notes([1318.0, 1760.0], 0.07, 0.25)),
		"quest": _wav(_notes([392.0, 523.0, 659.0], 0.13, 0.3)),
		"upgrade": _wav(_notes([440.0, 880.0, 1320.0], 0.09, 0.3)),
		"die": _wav(_die(rng)),
		"slam": _wav(_explode(rng)),
	}
