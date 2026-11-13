extends Node
# Beat clock synced to the song's playback position.
# t = heard song time (playback position + time since last mix - output
# latency - calibration). Beat k of a loop sits at offset + k * spb.
# Fallbacks: if the audio position never advances (dummy driver, decode
# failure) the clock runs on the wall clock; in --bot test runs it runs on
# the unscaled frame clock so a slow software renderer can't desync it.

signal beat(index, downbeat)

const SONG = {"id": "sleezetroit", "name": "SLEEZETROIT", "file": "res://assets/music/sleezetroit.mp3", "bpm": 100.0, "offset": 0.296}

var bpm = 100.0
var spb = 0.6
var offset = 0.296
var cal = 0.0            # seconds; + means "audio reaches the ear later"
var length = 1.0
var player : AudioStreamPlayer
var mode = "audio"       # audio | wall | sim
var loops = 0
var _last_pos = -1.0
var _stall = 0.0
var _wall = 0.0
var _last_ticks = 0
var t = 0.0              # absolute heard time (monotonic across loops)
var beat_index = -1
var running = false

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	player = AudioStreamPlayer.new()
	player.bus = "Master"
	add_child(player)

func start(song = SONG):
	bpm = song.bpm; spb = 60.0 / bpm; offset = song.offset
	var st = load(song.file)
	if st:
		if "loop" in st:
			st.loop = true
		player.stream = st
		length = st.get_length()
		if length <= 0.1: length = 230.0
		player.volume_db = -4.0
		player.play()
	else:
		length = 230.0
	if G.bot:
		mode = "sim"
	loops = 0; _last_pos = -1.0; _stall = 0.0; _wall = 0.0; t = 0.0; beat_index = -1
	_last_ticks = OS.get_ticks_usec()
	running = true

func set_paused(p):
	player.stream_paused = p

func _process(delta):
	if not running:
		return
	var now_us = OS.get_ticks_usec()
	var real = (now_us - _last_ticks) / 1000000.0
	_last_ticks = now_us
	if get_tree().paused:
		return
	if mode == "sim":
		_wall += G.real_delta(delta)
		t = _wall
	elif mode == "wall":
		_wall += real
		t = _wall
	else:
		var pos = player.get_playback_position()
		if player.playing and pos == _last_pos:
			_stall += real
			if _stall > 0.6:
				mode = "wall"; _wall = t
				print("[Beat] audio clock stalled -> wall clock")
		else:
			_stall = 0.0
		if _last_pos >= 0 and pos < _last_pos - 1.0:
			loops += 1
		_last_pos = pos
		pos += AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
		t = max(t, loops * length + pos)
	# beat signal
	var bi = int(floor(beat_float()))
	if bi != beat_index:
		beat_index = bi
		var local = int(floor((local_time() - offset - cal) / spb))
		G.on_beat_tick()
		emit_signal("beat", bi, local % 4 == 0)

func now():
	return t - cal

func local_time():
	return fmod(t, length)

func loop_base():
	return floor(t / length) * length

func beat_float():
	# beats since the first beat of the current loop + loops
	return floor(t / length) * 10000.0 + (local_time() - offset - cal) / spb

# absolute time of the beat grid point k (in the loop starting at base)
func _beat_time(base, k):
	return base + offset + cal + k * spb

func next_beat_after(tmin):
	# first beat strictly after absolute time tmin
	var base = floor(tmin / length) * length
	var k = ceil((tmin - base - offset - cal) / spb)
	var tb = _beat_time(base, k)
	if tb - base > length:
		tb = _beat_time(base + length, 0)
	if tb <= tmin:
		tb += spb
	return tb

func nearest_offset(at = -1.0):
	var x = t if at < 0 else at
	var base = floor(x / length) * length
	var k = round((x - base - offset - cal) / spb)
	return abs(x - _beat_time(base, k))

func phase():
	# 0 at the beat -> 1 just before the next
	var b = beat_float()
	return b - floor(b)

func seconds_to_next(tmin_ahead = 0.0):
	return next_beat_after(t + tmin_ahead) - t
