extends Node
class_name Sfx

## Compact sound pool. Gameplay impacts are procedurally generated into
## AudioStreamWAV buffers; the match-opening voice is an imported MP3 reference
## played at its natural pitch. Freeze/resume use tiny, low-level cues: they
## mark the rhythm without becoming a loud sound heard every few seconds.
##
## Everything is short and quiet on purpose: the sounds are there to confirm
## that something happened during the 0.75s execution burst, not to be heard.

const RATE := 22050
const VOLUME_DB := -6.0     # ~50% amplitude
const VOICES := 8           # round-robin pool, so overlapping hits all sound
const CUTOFF_FADE := 0.08
const TITLE_VOICE := preload("res://assets/audio/za-warudo-title.mp3")

var muted: bool = false
var master_volume: float = 1.0

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _rng := RandomNumberGenerator.new()
var _stop_at: Array[float] = []
var _base_db: Array[float] = []
var _pitch := {"title": 1.0}
var _cutoff := {"title": 3.50, "muda": 1.38}
var _gain_db := {"title": -4.0, "muda": -1.5, "explosion": -3.0,
	"freeze": -18.0, "resume": -20.0,
	"ui_move": -15.0, "ui_accept": -12.0}


func _ready() -> void:
	_rng.seed = 1337
	_streams["shoot"] = _shoot()
	_streams["hit"] = _hit()
	_streams["thud"] = _thud()
	_streams["break"] = _break()
	_streams["clash"] = _clash()
	_streams["explosion"] = _explosion()
	_streams["freeze"] = _freeze()
	_streams["resume"] = _resume()
	_streams["ui_move"] = _ui_move()
	_streams["ui_accept"] = _ui_accept()
	_streams["muda"] = _muda_chant()
	_streams["title"] = TITLE_VOICE
	_stop_at.resize(VOICES)
	_stop_at.fill(0.0)
	_base_db.resize(VOICES)
	_base_db.fill(VOLUME_DB)
	for i in VOICES:
		var pl := AudioStreamPlayer.new()
		pl.volume_db = VOLUME_DB
		add_child(pl)
		_players.append(pl)


func play(which: String) -> void:
	if muted or not _streams.has(which):
		return
	var slot: int = _next
	var pl: AudioStreamPlayer = _players[slot]
	_next = (_next + 1) % VOICES
	pl.stream = _streams[which]
	pl.pitch_scale = _pitch.get(which, 1.0)
	_base_db[slot] = VOLUME_DB + _gain_db.get(which, 0.0) \
		+ linear_to_db(maxf(master_volume, 0.001))
	pl.volume_db = _base_db[slot]
	pl.play()
	var cutoff: float = _cutoff.get(which, 0.0)
	_stop_at[slot] = float(Time.get_ticks_msec()) * 0.001 + cutoff if cutoff > 0.0 else 0.0


func _process(_delta: float) -> void:
	var now: float = float(Time.get_ticks_msec()) * 0.001
	for i in _stop_at.size():
		if _stop_at[i] <= 0.0:
			continue
		var remaining: float = _stop_at[i] - now
		if remaining <= 0.0:
			_players[i].stop()
			_stop_at[i] = 0.0
		elif remaining < CUTOFF_FADE:
			var fade: float = maxf(remaining / CUTOFF_FADE, 0.001)
			_players[i].volume_db = _base_db[i] + linear_to_db(fade)
		else:
			_players[i].volume_db = _base_db[i]


func toggle_mute() -> bool:
	muted = not muted
	if muted:
		for i in _players.size():
			var pl: AudioStreamPlayer = _players[i]
			pl.stop()
			_stop_at[i] = 0.0
	return muted


func set_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	muted = master_volume <= 0.001
	if muted:
		for i in _players.size():
			_players[i].stop()
			_stop_at[i] = 0.0


func _exit_tree() -> void:
	for player in _players:
		player.stop()


# ------------------------------------------------------------- synthesis ----

## Knife release: a quick downward chirp, like a blade cutting air.
func _shoot() -> AudioStreamWAV:
	var n := int(RATE * 0.075)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var u: float = float(i) / float(n)
		var t: float = float(i) / float(RATE)
		var f: float = lerpf(880.0, 360.0, u * u)
		s[i] = _square(t, f) * pow(1.0 - u, 2.2) * 0.55
	return _wav(s)


## Taking a knife: low square thump under a short noise crack.
func _hit() -> AudioStreamWAV:
	var n := int(RATE * 0.22)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var u: float = float(i) / float(n)
		var t: float = float(i) / float(RATE)
		var body: float = _square(t, lerpf(220.0, 70.0, u)) * pow(1.0 - u, 1.6)
		var crack: float = _rng.randf_range(-1.0, 1.0) * pow(1.0 - u, 7.0)
		s[i] = clampf(body * 0.6 + crack * 0.5, -1.0, 1.0) * 0.85
	return _wav(s)


## Knife burying itself in ground or a platform: a dry click.
func _thud() -> AudioStreamWAV:
	var n := int(RATE * 0.06)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var u: float = float(i) / float(n)
		var t: float = float(i) / float(RATE)
		var tone: float = _square(t, lerpf(300.0, 120.0, u))
		var grit: float = _rng.randf_range(-1.0, 1.0) * 0.4
		s[i] = (tone * 0.7 + grit) * pow(1.0 - u, 3.5) * 0.5
	return _wav(s)


## Platform giving way: a longer descending crunch.
func _break() -> AudioStreamWAV:
	var n := int(RATE * 0.34)
	var s := PackedFloat32Array()
	s.resize(n)
	var smooth := 0.0
	for i in n:
		var u: float = float(i) / float(n)
		var t: float = float(i) / float(RATE)
		# crude one-pole lowpass on the noise so it reads as rubble, not hiss
		smooth = lerpf(smooth, _rng.randf_range(-1.0, 1.0), 0.35)
		var tone: float = _square(t, lerpf(320.0, 60.0, u))
		s[i] = clampf(smooth * 0.75 + tone * 0.35, -1.0, 1.0) * pow(1.0 - u, 1.9) * 0.8
	return _wav(s)


## Blast: a hard transient over a low, rapidly falling pressure wave.
func _explosion() -> AudioStreamWAV:
	var n := int(RATE * 0.42)
	var s := PackedFloat32Array()
	s.resize(n)
	var smooth := 0.0
	for i in n:
		var u: float = float(i) / float(n)
		var t: float = float(i) / float(RATE)
		smooth = lerpf(smooth, _rng.randf_range(-1.0, 1.0), 0.18)
		var body := sin(TAU * lerpf(105.0, 38.0, u) * t) * pow(1.0 - u, 1.45)
		var crack := smooth * pow(1.0 - u, 5.0)
		s[i] = clampf(body * 0.78 + crack * 0.88, -1.0, 1.0) * 0.88
	return _wav(s)


## Metallic knife-on-knife ring with a short noisy transient.
func _clash() -> AudioStreamWAV:
	var n := int(RATE * 0.18)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var u: float = float(i) / float(n)
		var t: float = float(i) / float(RATE)
		var ring: float = (sin(TAU * 1850.0 * t) + sin(TAU * 2470.0 * t) * 0.45) \
			* pow(1.0 - u, 3.0)
		var echo := 0.0
		if t > 0.055:
			var v: float = clampf((t - 0.055) / 0.125, 0.0, 1.0)
			echo = (sin(TAU * 2240.0 * (t - 0.055))
				+ sin(TAU * 2910.0 * (t - 0.055)) * 0.35) * pow(1.0 - v, 3.2) * 0.72
		var crack: float = _rng.randf_range(-1.0, 1.0) * pow(1.0 - u, 12.0)
		s[i] = clampf(ring * 0.46 + echo * 0.42 + crack * 0.55, -1.0, 1.0)
	return _wav(s)


## Rapid synthetic "muda" chant for the SUPER freeze frame. A pulsed glottal
## fundamental plus two moving formants gives it a voice-like body without
## requiring a bundled speech sample; each word has a closed "mu" and a harder
## noisy "da" onset.
func _muda_chant() -> AudioStreamWAV:
	var word_length := 0.18
	var words := 7
	var total := word_length * float(words) + 0.06
	var n := int(RATE * total)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t: float = float(i) / float(RATE)
		var word: int = mini(int(t / word_length), words - 1)
		var local: float = fposmod(t, word_length)
		var in_da: bool = local >= word_length * 0.47
		var phase_t: float = local - word_length * 0.47 if in_da else local
		var phase_len: float = word_length * (0.53 if in_da else 0.47)
		var u: float = clampf(phase_t / phase_len, 0.0, 1.0)
		var env: float = sin(PI * clampf(u, 0.0, 1.0))
		var fundamental: float = 148.0 + float(word % 3) * 7.0
		var glottal: float = _square(t, fundamental) * 0.30 + sin(TAU * fundamental * t) * 0.22
		var f1: float = 690.0 if in_da else 330.0
		var f2: float = 1280.0 if in_da else 880.0
		var formants: float = sin(TAU * f1 * t) * 0.28 + sin(TAU * f2 * t) * 0.13
		var onset: float = 0.0
		if in_da and phase_t < 0.018:
			onset = _rng.randf_range(-1.0, 1.0) * (1.0 - phase_t / 0.018) * 0.34
		var word_tail: float = 1.0 if word < words - 1 else maxf(0.0, 1.0 - u * u)
		s[i] = clampf((glottal + formants + onset) * env * word_tail * 0.82, -1.0, 1.0)
	return _wav(s)


## A very soft descending breath: punctuation, not an announcement.
func _freeze() -> AudioStreamWAV:
	var n := int(RATE * 0.11)
	var s := PackedFloat32Array()
	s.resize(n)
	var smooth := 0.0
	for i in n:
		var u: float = float(i) / float(n)
		var t: float = float(i) / float(RATE)
		var f: float = lerpf(310.0, 115.0, u)
		smooth = lerpf(smooth, _rng.randf_range(-1.0, 1.0), 0.08)
		var envelope: float = sin(PI * clampf(u * 1.7, 0.0, 1.0)) * pow(1.0 - u, 1.8)
		s[i] = clampf(sin(TAU * f * t) * 0.30 + smooth * 0.10, -1.0, 1.0) * envelope
	return _wav(s)


## A tiny upward glass tick when the execution window releases.
func _resume() -> AudioStreamWAV:
	var n := int(RATE * 0.065)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var u: float = float(i) / float(n)
		var t: float = float(i) / float(RATE)
		var f: float = lerpf(420.0, 940.0, u)
		var envelope: float = sin(PI * clampf(u * 2.2, 0.0, 1.0)) * pow(1.0 - u, 2.4)
		s[i] = sin(TAU * f * t) * envelope * 0.32
	return _wav(s)


## Quiet menu ticks confirm focus and activation without competing with the
## match-opening voice or the much brighter knife-on-knife transients.
func _ui_move() -> AudioStreamWAV:
	var n := int(RATE * 0.035)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var u: float = float(i) / float(n)
		var t: float = float(i) / float(RATE)
		s[i] = sin(TAU * lerpf(560.0, 720.0, u) * t) * pow(1.0 - u, 3.6) * 0.26
	return _wav(s)


func _ui_accept() -> AudioStreamWAV:
	var n := int(RATE * 0.085)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var u: float = float(i) / float(n)
		var t: float = float(i) / float(RATE)
		var first := sin(TAU * 520.0 * t) * pow(1.0 - u, 3.0)
		var second := 0.0
		if t > 0.032:
			var v := clampf((t - 0.032) / 0.053, 0.0, 1.0)
			second = sin(TAU * 780.0 * (t - 0.032)) * pow(1.0 - v, 3.0)
		s[i] = (first * 0.20 + second * 0.30)
	return _wav(s)


static func _square(t: float, freq: float) -> float:
	return 1.0 if fposmod(t * freq, 1.0) < 0.5 else -1.0


static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w
