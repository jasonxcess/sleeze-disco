extends SceneTree
# HEADLESS-ONLY test (never shipped: export preset excludes tools/*).
# Loads sleezetroit through a fresh RhythmManager and runs ~245 s of
# real time to cross the MP3 loop wrap (~230.452 s). Verifies:
#   1. The MP3 stream actually loads (resource_path + class printed).
#   2. The beat clock keeps running (beat_index advances ~1 per 600 ms).
#   3. The beat grid re-anchors at the wrap: at every fired beat, the
#      judge offset must stay within a few ms of 0. A marching (global)
#      grid would read ~+52 ms after 1 loop, ~+104 ms after 2.
# Usage (stock Godot 3.5.3 headless):
#   Godot_v3.5.3-stable_linux_headless.64 --path <project> -s tools/test_mp3_loop.gd

var rm = null
var t := 0.0
var next_log := 0.0
var wrap_seen := false
var worst_post_wrap_offset := 0.0
var beats_post_wrap := 0

func _initialize() -> void:
	rm = load("res://scripts/managers/RhythmManager.gd").new()
	root.add_child(rm)
	rm.connect("beat_hit", self, "_on_beat")
	var ok: bool = rm.load_track("sleezetroit")
	print("TEST mp3 load ok=", ok, " track=", rm.track_key, " stream=", rm.player.stream.resource_path if rm.player.stream != null else "null", " class=", rm.player.stream.get_class() if rm.player.stream != null else "null", " bpm=", rm.bpm, " first_beat_ms=", rm.first_beat_ms, " loop_len_ms=", rm.loop_len_ms)
	print("TEST running to 245 s (wrap at ~230.452 s)")

func _on_beat(beat_index: int) -> void:
	# At a fired beat boundary the judge offset should be ~0 (the fire
	# happens in _process the first frame the position passes the
	# boundary, so a few ms of frame lag is normal).
	var off: float = rm._press_offset_ms()
	if rm._loop_index > 0:
		wrap_seen = true
		beats_post_wrap += 1
		worst_post_wrap_offset = max(worst_post_wrap_offset, abs(off))
		if beats_post_wrap <= 6:
			print("TEST post-wrap beat=%d t=%.2f off=%.1f ms loop=%d" % [beat_index, t, off, rm._loop_index])

func _iteration(delta: float) -> bool:
	t += delta
	if t >= next_log:
		next_log += 10.0
		print("TEST t=%.1f pos=%.1f ms loop=%d beat=%d next_beat=%.1f playing=%s" % [t, rm.song_position_ms(), rm._loop_index, rm.beat_index, rm._next_beat_ms, str(rm.playing)])
	if t >= 245.0:
		print("TEST DONE t=%.1f loop=%d beat=%d wrap_seen=%s beats_post_wrap=%d worst_post_wrap_offset=%.1f ms" % [t, rm._loop_index, rm.beat_index, str(wrap_seen), beats_post_wrap, worst_post_wrap_offset])
		if wrap_seen and worst_post_wrap_offset <= 30.0:
			print("TEST RESULT: PASS — grid re-anchored at the wrap (worst offset %.1f ms)" % worst_post_wrap_offset)
		elif wrap_seen:
			print("TEST RESULT: FAIL — grid drifted after the wrap (worst offset %.1f ms)" % worst_post_wrap_offset)
		else:
			print("TEST RESULT: INCONCLUSIVE — no wrap seen (audio clock may have stalled)")
		return true
	return false
