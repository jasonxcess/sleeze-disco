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
# (tools/render_tracks.py). Beats are periodic from the BPM — no beatmap
# files. The loop is tracked explicitly (loop_index) so the absolute beat
# count never resets when the stream wraps.

signal beat_hit(beat_index)              # fired once per beat boundary
signal beat_judged(judgement, offset_ms, multiplier)
signal song_started(song_name)
signal song_finished

const LOOP_LEN_MS := 60000.0   # every loop is exactly 60 s (integer beats)
const FIRST_BEAT_MS := 50.0    # web: nextBeatTime = currentTime + 0.05

var player: AudioStreamPlayer
var sfx: AudioStreamPlayer

var song_name := ""
var track_key := ""
var bpm := 120
var offset_ms := 0.0
var calibration_ms := 0.0   # per-device audio latency, set from the title screen
var playing := false
var beat_index := -1        # absolute beat count since play (-1 = count-in)

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

# Load + start a v7.6 track by key. Beats are generated from the BPM.
func load_track(p_key: String) -> bool:
	if not BeatData.TRACKS.has(p_key):
		push_error("RhythmManager: unknown track " + p_key)
		return false
	var t: Dictionary = BeatData.TRACKS[p_key]
	track_key = p_key
	song_name = String(t["name"])
	bpm = int(t["bpm"])
	var stream: AudioStreamOGGVorbis = load(String(t["ogg"]))
	if stream == null:
		push_error("RhythmManager: cannot load " + String(t["ogg"]))
		return false
	# Godot 3.x AudioStreamOGGVorbis has loop + loop_offset only (no
	# loop_begin/loop_end — those are Godot 4). The 60 s loop restarts
	# at 0; the beat clock tracks the wrap itself (see _update_loop).
	stream.loop = true
	stream.loop_offset = 0.0
	player.stream = stream
	player.play()
	playing = true
	beat_index = -1
	_loop_index = 0
	_last_pos_ms = -1.0
	_next_beat_ms = FIRST_BEAT_MS
	set_process(true)
	emit_signal("song_started", song_name)
	return true

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
# Loop-aware: the stream wraps every 60 s, the count does not.
# Wrap detection runs here too, so any reader (judgement, telegraph,
# phase) is correct even in the frame right after a wrap.
func song_position_ms() -> float:
	if player.stream == null:
		return 0.0
	var raw: float = player.get_playback_position() * 1000.0
	_update_loop(raw)
	return _loop_index * LOOP_LEN_MS + raw - calibration_ms

func song_position_sec() -> float:
	return song_position_ms() / 1000.0

func beat_dur_ms() -> float:
	return 60000.0 / float(max(bpm, 1))

func beat_dur_sec() -> float:
	return 60.0 / float(max(bpm, 1))

# 0.0..1.0 inside the current beat interval. 0 = exactly on the beat.
func beat_phase01() -> float:
	if not playing:
		return 0.0
	var pos := song_position_ms()
	var since := fmod(pos - FIRST_BEAT_MS, beat_dur_ms())
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
	var pos := song_position_ms()
	var rel := pos - FIRST_BEAT_MS
	var k := round(rel / beat_dur_ms())
	var nearest := FIRST_BEAT_MS + k * beat_dur_ms()
	return pos - nearest

func _process(_delta: float) -> void:
	if not playing or get_tree().paused:
		return
	var pos := song_position_ms()
	# Fire every beat boundary passed (catch-up loop covers hit-stop gaps).
	while _next_beat_ms <= pos:
		beat_index += 1
		emit_signal("beat_hit", beat_index)
		_next_beat_ms += beat_dur_ms()

# Detect the 60 s loop wrap: the raw position falls back to ~0.
# Idempotent — safe to call from every reader.
func _update_loop(raw_ms: float) -> void:
	if _last_pos_ms >= 0.0 and raw_ms < _last_pos_ms - 500.0:
		_loop_index += 1
	_last_pos_ms = raw_ms
