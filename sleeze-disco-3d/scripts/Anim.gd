extends Reference
# PSX-style animation driver (v0.2): plain AnimationPlayer, one baked clip
# at a time. No AnimationTree, no blend nodes, no per-frame tree evaluation.
# The tree was 4 TimeSeek + 2 Blend2 + TimeScale + Blend2 nodes per fighter,
# evaluated every frame for ~5 fighters — cheap on desktop, dead weight on a
# 444 MHz Vita CPU next to 11 skeletons. Same public API as the tree driver
# it replaces (setup / clip_len / update_loco / play / stop / playing /
# update, plus the phase / act_time / act_name fields callers read), so
# Player.gd and Enemy.gd are unchanged apart from the IK/ragdoll removal.
#
# Locomotion: ONE ladder clip at a time, playback speed scaled so the cycle
# matches ground speed (stride matching without a tree: rate = speed /
# natural_speed, so the feet cover exactly the ground the body covers).
# The stride phase is kept across clip switches (seek to phase * length),
# so walk -> run does not pop. Actions: play the clip on the same player
# with a small blend, resume locomotion when the action ends.

var ap : AnimationPlayer
var ladder = []          # [[clip, natural_speed, length]]
var phase = 0.0          # 0..1 stride cycle fraction (footsteps read this)
var _cur_loco = ""
var _cur_rate = 1.0
# action state
var act_name = ""
var act_time = 0.0       # clip time of the playing action
var act_rate = 1.0
var act_end = 0.0        # clip time where the action ends
var fade_out = 0.16

func setup(owner_node, anim_player, loco):
	ap = anim_player
	for n in ["idle", "walk", "run", "sprint", "dance"]:
		if ap.has_animation(n):
			ap.get_animation(n).loop = true
	ladder = loco
	_cur_loco = "idle"
	_cur_rate = 1.0
	ap.play("idle", 0.0, 1.0)

func clip_len(clip):
	if ap.has_animation(clip):
		return ap.get_animation(clip).length
	return 1.0

func update_loco(speed, delta):
	# pick the bracket on the ladder, then the nearer of the two clips
	var i = 0
	while i < ladder.size() - 2 and speed > ladder[i + 1][1]:
		i += 1
	var a = ladder[i]
	var b = ladder[i + 1]
	var w = 0.0
	if b[1] > a[1]:
		w = clamp((speed - a[1]) / (b[1] - a[1]), 0.0, 1.0)
	var pick = a if w < 0.5 else b
	# stride (metres per cycle) of the picked clip; phase advances by the
	# ground actually covered, so the feet stay planted at any speed
	var stride = pick[1] * pick[2]
	phase = fmod(phase + delta * speed / max(stride, 0.05), 1.0)
	var rate = 1.0
	if pick[1] > 0.01:
		rate = clamp(speed / pick[1], 0.6, 2.0)
	if act_name != "":
		# an action owns the player right now; keep the phase for resume
		_cur_loco = pick[0]
		_cur_rate = rate
		return
	if pick[0] != _cur_loco:
		_cur_loco = pick[0]
		_cur_rate = rate
		ap.play(pick[0], 0.08, rate)
		ap.seek(phase * pick[2], true)
	elif abs(rate - _cur_rate) > 0.05:
		_cur_rate = rate
		ap.playback_speed = rate

func play(clip, start, rate, end_time = -1.0, fin = 0.07, fout = 0.16):
	# one clip replaces whatever is playing, blended in over `fin` seconds
	ap.play(clip, fin, rate)
	ap.seek(start, true)
	act_name = clip
	act_time = start
	act_rate = rate
	act_end = clip_len(clip) if end_time < 0 else end_time
	fade_out = fout

func stop(fout = 0.16):
	if act_name == "":
		return
	act_name = ""
	_resume_loco(fout)

func playing():
	return act_name != ""

func _resume_loco(blend):
	if _cur_loco == "":
		_cur_loco = "idle"
	ap.play(_cur_loco, blend, _cur_rate)
	ap.seek(phase * clip_len(_cur_loco), true)

func update(delta):
	if act_name != "":
		act_time += delta * act_rate
		if act_time >= act_end:
			act_name = ""
			_resume_loco(fade_out)
