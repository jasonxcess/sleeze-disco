extends Node
const BeatData := preload("res://scripts/util/BeatData.gd")
# SLEEZE DISCO — RhythmManager (autoload, Godot 3.5 / GDScript).
#
# Drift-free audio sync, ported from web v7.6 (PORT_SPEC.md §1.2, §8).
# The audio clock is the ONLY clock: every judgement compares
# AudioStreamPlayer.get_playback_position() against the periodic beat
# grid. Frame time is never used for timing, so a dropped frame, a
# hit-stop freeze (Engine.time_scale = 0) or a pause can never knock
# the beat off — the music keeps its own time and the game reads it.
#
# The manager runs with pause_mode PROCESS so beat boundaries keep
# firing through hit-stop (the web queue timer runs on the audio clock,
# not the sim). It still respects tree pause (see _process).
#
# Windows (web v7.6):
#   PERFECT  |offset| <= 65 ms   -> 1.5x damage
#   GOOD     |offset| <= 130 ms  -> 1.1x damage
#   HIT      beyond 130 ms      -> 1.0x, normal hit, NEVER a penalty.
#   MISS     parry-press only, past 130 ms -> 0.6x (parry payoff only).
# Off-beat attacks still land. Mashing looks like a fight scene; timing pays.
#
# Songs are the v7.6 TRACKS: 60 s OGG loops rendered from the patterns
# (tools/render_tracks.py), plus sleezetroit — Shawn's own song as a full
# MP3 (100 BPM, first beat 0.296 s). Beats are periodic from the BPM — no
# beatmap files. The loop is tracked explicitly (loop_index) so the
# absolute beat count never resets when the stream wraps, and the grid is
# re-anchored every loop: the MP3 is 230.452 s = 384.09 beats, so a global
# grid would drift ~52 ms per loop.

signal beat_hit(beat_index)              # fired once per beat boundary
signal beat_judged(judgement, offset_ms, multiplier)
signal song_started(song_name)
signal song_finished

const LOOP_LEN_MS := 60000.0   # synth loops: every loop is exactly 60 s (integer beats)
const FIRST_BEAT_MS := 50.0    # synth loops: web nextBeatTime = currentTime + 0.05

var player: AudioStreamPlayer
var sfx: AudioStreamPlayer

var song_name := ""
var track_key := ""
var bpm := 120
var offset_ms := 0.0
var calibration_ms := 0.0   # per-device audio latency, set from the title screen
var playing := false
var beat_index := -1        # absolute beat count since play (-1 = count-in)
var first_beat_ms := FIRST_BEAT_MS  # per-track: ms of the first beat in the loop
var loop_len_ms := LOOP_LEN_MS      # per-track: ms of one loop (MP3 = full song length)

var _loop_index := 0
var _last_pos_ms := -1.0
var _next_beat_ms := 0.0    # absolute ms of the next beat boundary
var _blips := {}

func _ready() -> void:
	# Node.PAUSE_MODE_PROCESS: the beat clock keeps running through
	# hit-stop (which pauses the tree) — Godot 3.x pause_mode.
	pause_mode = Node.PAUSE_MODE_PROCESS
	player = AudioStreamPlayer.new()
	player.name = "MusicPlayer"
	player.bus = "Master"
	add_child(player)
	sfx = AudioStreamPlayer.new()
	sfx.name = "SfxPlayer"
	sfx.bus = "Master"
	add_child(sfx)
	for n in ["perfect", "good", "dance", "rush", "notokens", "counter"]:
		_blips[n] = load("res://assets/audio/blip_" + n + ".wav")
	set_process(false)

# Load + start a track by key. Beats are generated from the BPM.
# Two kinds of track: the 60 s OGG synth loops (loop_len 60 s, first beat
# 50 ms) and full MP3 songs (sleezetroit: 230.452 s, first beat 296 ms).
# An MP3 entry that fails to load falls back to its "fallback" synth loop
# (same BPM) so the fight still has music.
func load_track(p_key: String) -> bool:
	if not BeatData.TRACKS.has(p_key):
		push_error("RhythmManager: unknown track " + p_key)
		return false
	var t: Dictionary = BeatData.TRACKS[p_key]
	var stream: AudioStream = _load_stream_for(t)
	if stream == null and t.has("fallback"):
		var fb_key := String(t["fallback"])
		push_warning("RhythmManager: " + p_key + " failed to load, falling back to " + fb_key)
		if not BeatData.TRACKS.has(fb_key):
			push_error("RhythmManager: unknown fallback track " + fb_key)
			return false
		t = BeatData.TRACKS[fb_key]
		p_key = fb_key
		stream = _load_stream_for(t)
	if stream == null:
		push_error("RhythmManager: cannot load " + p_key)
		return false
	track_key = p_key
	song_name = String(t["name"])
	bpm = int(t["bpm"])
	first_beat_ms = float(t.get("first_beat_ms", FIRST_BEAT_MS))
	if t.has("mp3"):
		# Full song, not a 60 s loop. The beat grid re-anchors every
		# loop (see _update_loop): the length is not an integer number
		# of beats (230.452 s at 100 BPM = 384.09 beats), so a global
		# grid would drift ~52 ms per loop.
		loop_len_ms = stream.get_length() * 1000.0
		if loop_len_ms <= 0.0:
			loop_len_ms = 230452.0
	else:
		loop_len_ms = LOOP_LEN_MS
	# Godot 3.x AudioStreamOGGVorbis and AudioStreamMP3 both have loop +
	# loop_offset (no loop_begin/loop_end — those are Godot 4). The loop
	# restarts at 0; the beat clock tracks the wrap itself (see _update_loop).
	stream.loop = true
	stream.loop_offset = 0.0
	player.stream = stream
	player.play()
	playing = true
	beat_index = -1
	_loop_index = 0
	_last_pos_ms = -1.0
	_next_beat_ms = first_beat_ms
	set_process(true)
	print("RhythmManager: track ", track_key, " -> ", player.stream.resource_path, " (", player.stream.get_class(), ") bpm=", bpm, " first_beat_ms=", first_beat_ms, " loop_len_ms=", loop_len_ms)
	emit_signal("song_started", song_name)
	return true

# MP3 entries load AudioStreamMP3, OGG entries AudioStreamOGGVorbis.
# Returns null when the file cannot be loaded.
func _load_stream_for(t: Dictionary) -> AudioStream:
	if t.has("mp3"):
		return load(String(t["mp3"])) as AudioStream
	if t.has("ogg"):
		return load(String(t["ogg"])) as AudioStream
	return null

# Back-compat shim for old callers: a beatmap path is no longer used.
# Beats come from the BPM. Kept so a stale call fails loudly, not silently.
func load_beatmap(_path: String) -> bool:
	push_error("RhythmManager: beatmap files are gone — use load_track()")
	return false

func play_song(_stream: AudioStream) -> void:
	push_error("RhythmManager: play_song is gone — use load_track()")

func stop_song() -> void:
	player.stop()
	playing = false
	set_process(false)
	emit_signal("song_finished")

func pause_song(paused: bool) -> void:
	player.stream_paused = paused

# Master clock: absolute ms of audio played, latency-corrected.
# Loop-aware: the stream wraps every loop (60 s synth loops, 230.452 s
# MP3), the count does not.
# Wrap detection runs here too, so any reader (judgement, telegraph,
# phase) is correct even in the frame right after a wrap.
func song_position_ms() -> float:
	if player.stream == null:
		return 0.0
	var raw: float = player.get_playback_position() * 1000.0
	_update_loop(raw)
	return _loop_index * loop_len_ms + raw - calibration_ms

func song_position_sec() -> float:
	return song_position_ms() / 1000.0

# Position (ms) inside the current loop, 0..loop_len. The beat grid is
# per-loop: the MP3 is 230.452 s = 384.09 beats, so a global grid would
# drift ~52 ms per loop. The 60 s synth loops are an integer beat count,
# so this changes nothing for them.
func _local_pos_ms() -> float:
	return song_position_ms() - _loop_index * loop_len_ms

func beat_dur_ms() -> float:
	return 60000.0 / float(max(bpm, 1))

func beat_dur_sec() -> float:
	return 60.0 / float(max(bpm, 1))

# 0.0..1.0 inside the current beat interval. 0 = exactly on the beat.
func beat_phase01() -> float:
	if not playing:
		return 0.0
	var since := fmod(_local_pos_ms() - first_beat_ms, beat_dur_ms())
	if since < 0.0:
		since += beat_dur_ms()
	return clamp(since / beat_dur_ms(), 0.0, 1.0)

func time_to_next_beat_ms() -> float:
	if not playing:
		return 0.0
	return max(_next_beat_ms - song_position_ms(), 0.0)

# The call the attack state machine makes, on the exact frame the player
# presses punch / kick / throw. Judged by the PRESS offset, not the fire
# time (the snap-to-beat queue fires later — see Player). Returns:
#   {"judgement": Judgement, "offset_ms": float, "multiplier": float}
# offset is signed: negative = early, positive = late.
func judge_attack() -> Dictionary:
	var off := _press_offset_ms()
	var j: int = BeatData.Judgement.HIT
	var mult := BeatData.MULT_HIT
	if abs(off) <= BeatData.PERFECT_MS:
		j = BeatData.Judgement.PERFECT
		mult = BeatData.MULT_PERFECT
	elif abs(off) <= BeatData.GOOD_MS:
		j = BeatData.Judgement.GOOD
		mult = BeatData.MULT_GOOD
	emit_signal("beat_judged", j, off, mult)
	return {"judgement": j, "offset_ms": off, "multiplier": mult}

# Parry is judged at press time with the web judge(): past 130 ms is a
# MISS that still parries, but pays almost nothing.
func judge_parry() -> Dictionary:
	var off := _press_offset_ms()
	var j: int = BeatData.Judgement.MISS
	var mult := BeatData.MULT_PARRY_MISS
	if abs(off) <= BeatData.PERFECT_MS:
		j = BeatData.Judgement.PERFECT
		mult = BeatData.MULT_PERFECT
	elif abs(off) <= BeatData.GOOD_MS:
		j = BeatData.Judgement.GOOD
		mult = BeatData.MULT_GOOD
	emit_signal("beat_judged", j, off, mult)
	return {"judgement": j, "offset_ms": off, "multiplier": mult}

func judgement_name(j: int) -> String:
	match j:
		BeatData.Judgement.PERFECT:
			return "PERFECT!"
		BeatData.Judgement.GOOD:
			return "GOOD"
		BeatData.Judgement.MISS:
			return "MISS"
		_:
			return "HIT"

func play_blip(blip_name: String) -> void:
	if _blips.has(blip_name):
		sfx.stream = _blips[blip_name]
		sfx.play()

func _press_offset_ms() -> float:
	if not playing:
		return 999.0
	var local := _local_pos_ms()
	var rel := local - first_beat_ms
	var k := round(rel / beat_dur_ms())
	var nearest := first_beat_ms + k * beat_dur_ms()
	return local - nearest

func _process(_delta: float) -> void:
	if not playing or get_tree().paused:
		return
	var pos := song_position_ms()
	# Fire every beat boundary passed (catch-up loop covers hit-stop gaps).
	while _next_beat_ms <= pos:
		beat_index += 1
		emit_signal("beat_hit", beat_index)
		_next_beat_ms += beat_dur_ms()

# Detect the loop wrap: the raw position falls back to ~0.
# Idempotent — safe to call from every reader. On a wrap, re-anchor the
# beat grid on the new loop (same as 3D Beat.gd): the MP3 loop is not an
# integer number of beats, so the marching grid would drift ~52 ms per
# loop. For the 60 s synth loops this is a no-op (60 s = integer beats).
func _update_loop(raw_ms: float) -> void:
	if _last_pos_ms >= 0.0 and raw_ms < _last_pos_ms - 500.0:
		_loop_index += 1
		_next_beat_ms = _loop_index * loop_len_ms + first_beat_ms
	_last_pos_ms = raw_ms
