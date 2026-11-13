extends CanvasLayer
# Always-on FPS + stage overlay. While loading it also shows a big stage name.
# v0.2.1: also writes a frame-cost line to boot.log every 2 s, so a Vita run
# says where the frame time goes (script / physics / render+driver submit).

var small : Label
var big : Label
var font : DynamicFont
var _t = 0.0
var stage = ""
var done = false
# frame-cost sampling: render = frame_pre_draw -> frame_post_draw (Godot's
# GLES2 draw submission + driver work on the main thread)
var _pre_us = 0
var _render_us = 0
var _render_max_us = 0
var _frames = 0
var _frame_us = 0
var _frame_max_us = 0
var _last_us = 0
var _log_t = 2.0

func _ready():
	layer = 100
	pause_mode = Node.PAUSE_MODE_PROCESS
	font = DynamicFont.new()
	font.font_data = load("res://assets/fonts/DejaVuSans-Bold.ttf")
	font.size = 16
	small = Label.new()
	small.add_font_override("font", font)
	small.rect_position = Vector2(6, 4)
	small.add_color_override("font_color", Color(0.4, 1, 0.9))
	add_child(small)
	var bf = DynamicFont.new()
	bf.font_data = font.font_data
	bf.size = 28
	big = Label.new()
	big.add_font_override("font", bf)
	big.rect_position = Vector2(40, 220)
	big.add_color_override("font_color", Color(1, 0.3, 0.8))
	add_child(big)
	VisualServer.connect("frame_pre_draw", self, "_on_pre_draw")
	VisualServer.connect("frame_post_draw", self, "_on_post_draw")
	G.blog("diag: profile %s flags %s driver=%s adapter=%s" % [G.profile, str(G.cfg()), OS.get_video_driver_name(OS.get_current_video_driver()), VisualServer.get_video_adapter_name()])
	G.blog("diag: sw_skin_fallback=%s force_sw_skin=%s" % [str(ProjectSettings.get_setting("rendering/quality/skinning/software_skinning_fallback")), str(ProjectSettings.get_setting("rendering/quality/skinning/force_software_skinning"))])

func _on_pre_draw():
	_pre_us = OS.get_ticks_usec()

func _on_post_draw():
	if _pre_us == 0:
		return
	var r = OS.get_ticks_usec() - _pre_us
	_render_us += r
	_render_max_us = max(_render_max_us, r)
	var now = OS.get_ticks_usec()
	if _last_us > 0:
		var f = now - _last_us
		_frame_us += f
		_frame_max_us = max(_frame_max_us, f)
		_frames += 1
	_last_us = now

func _count(n, cls):
	var c = 1 if n.is_class(cls) else 0
	for ch in n.get_children():
		c += _count(ch, cls)
	return c

func _log_cost():
	if _frames == 0:
		return
	var P = Performance
	var skels = _count(get_tree().root, "Skeleton")
	var aps = 0
	for ap in _find_aps(get_tree().root, []):
		if ap.is_playing() and ap.playback_process_mode != AnimationPlayer.ANIMATION_PROCESS_MANUAL:
			aps += 1
	G.blog("cost: fps %d | frame avg %.1f max %.1f ms | render avg %.1f max %.1f ms | perf.process %.1f ms | perf.physics %.1f ms | draws %d verts %d mat %d shd %d surf %d | 2d items %d 2d draws %d | skel %d animating %d | vmem %.1f MB tex %.1f MB" % [
		Engine.get_frames_per_second(),
		_frame_us / 1000.0 / _frames, _frame_max_us / 1000.0,
		_render_us / 1000.0 / _frames, _render_max_us / 1000.0,
		P.get_monitor(P.TIME_PROCESS) * 1000.0, P.get_monitor(P.TIME_PHYSICS_PROCESS) * 1000.0,
		P.get_monitor(P.RENDER_DRAW_CALLS_IN_FRAME), P.get_monitor(P.RENDER_VERTICES_IN_FRAME),
		P.get_monitor(P.RENDER_MATERIAL_CHANGES_IN_FRAME), P.get_monitor(P.RENDER_SHADER_CHANGES_IN_FRAME),
		P.get_monitor(P.RENDER_SURFACE_CHANGES_IN_FRAME),
		P.get_monitor(P.RENDER_2D_ITEMS_IN_FRAME), P.get_monitor(P.RENDER_2D_DRAW_CALLS_IN_FRAME),
		skels, aps,
		P.get_monitor(P.RENDER_VIDEO_MEM_USED) / 1048576.0, P.get_monitor(P.RENDER_TEXTURE_MEM_USED) / 1048576.0])
	_frames = 0; _frame_us = 0; _frame_max_us = 0; _render_us = 0; _render_max_us = 0

func _find_aps(n, out):
	if n is AnimationPlayer:
		out.append(n)
	for ch in n.get_children():
		_find_aps(ch, out)
	return out

func set_stage(s):
	stage = s
	if big:
		big.text = ("LOADING: " + s) if s != "" else ""
	_refresh()

func loaded():
	done = true
	big.text = ""

func _refresh():
	if small:
		small.text = "%d fps  [%s]  %s" % [Engine.get_frames_per_second(), G.profile, stage]

func _process(delta):
	_log_t -= delta / max(Engine.time_scale, 0.001)
	if _log_t <= 0.0:
		_log_t = 2.0
		_log_cost()
	_t -= delta
	if _t <= 0.0:
		_t = 0.25
		_refresh()
