extends CanvasLayer
# HUD: HP / Fever / stars, score + combo + rank, beat bar, judgement pops,
# enemy beat-countdown telegraph markers (projected 2D, cheap), lock reticle,
# banner, pause + latency calibration, FPS / draw-call readout.

var arena
var font : DynamicFont
var font_big : DynamicFont
var font_small : DynamicFont
var root : Control
var draw : Control
var pops = []      # {text, color, pos3d, t}
var banner = ""
var banner_t = 0.0
var show_fps = true
var pause_panel : Control
var pause_label : Label
var beat_pulse = 0.0
var down_pulse = false

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	var data = load("res://assets/fonts/DejaVuSans-Bold.ttf")
	font = DynamicFont.new(); font.font_data = data; font.size = 14; font.outline_size = 1; font.outline_color = Color(0, 0, 0)
	font_big = DynamicFont.new(); font_big.font_data = data; font_big.size = 30; font_big.outline_size = 2; font_big.outline_color = Color(0, 0, 0)
	font_small = DynamicFont.new(); font_small.font_data = data; font_small.size = 10; font_small.outline_size = 1; font_small.outline_color = Color(0, 0, 0)
	root = Control.new(); root.anchor_right = 1; root.anchor_bottom = 1; root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	draw = Control.new(); draw.anchor_right = 1; draw.anchor_bottom = 1; draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(draw)
	draw.connect("draw", self, "_on_draw")
	pause_panel = ColorRect.new()
	pause_panel.color = Color(0.03, 0, 0.08, 0.78)
	pause_panel.anchor_right = 1; pause_panel.anchor_bottom = 1
	pause_panel.visible = false
	root.add_child(pause_panel)
	pause_label = Label.new()
	pause_label.add_font_override("font", font)
	pause_label.anchor_right = 1; pause_label.anchor_bottom = 1
	pause_label.align = Label.ALIGN_CENTER; pause_label.valign = Label.VALIGN_CENTER
	pause_panel.add_child(pause_label)
	G.connect("judged", self, "_on_judged")
	Beat.connect("beat", self, "_on_beat")

func _on_judged(text, color, pos):
	if pos == null:
		show_banner(text, 1.4)
	else:
		pop(text, color, pos)

func _on_beat(_i, down):
	beat_pulse = 1.0
	down_pulse = down

func pop(text, color, pos3d):
	pops.append({"text": text, "color": color, "pos": pos3d, "t": 0.0})
	if pops.size() > 8:
		pops.pop_front()

func show_banner(t, dur = 2.0):
	banner = t; banner_t = dur

func set_paused(p):
	pause_panel.visible = p
	_update_pause_text()

func _update_pause_text():
	pause_label.text = "PAUSED\n\nSTART  resume\nD-PAD ◀ ▶  beat latency  %+d ms\nSELECT  restart arena\n\nPERFECT ±65 ms · GOOD ±130 ms\n\nSleeze: WardsterSAW · Vex: murilo.kleine (CC BY 4.0) · Thugs: bumstrum (CC BY 4.0)\nClub: 00amza (CC BY 4.0) · Motion: Adobe Mixamo · SFX + FX: Kenney (CC0)\nMusic: SLEEZETROIT by SleezeTeamJason · Font: DejaVu" % int(round(Beat.cal * 1000.0))

func _process(delta):
	var rd = G.real_delta(delta) if not get_tree().paused else delta
	for p in pops:
		p.t += rd
	while pops.size() > 0 and pops[0].t > 0.9:
		pops.pop_front()
	banner_t = max(0.0, banner_t - rd)
	beat_pulse = max(0.0, beat_pulse - rd * 3.5)
	if Input.is_action_just_pressed("pause"):
		arena._toggle_pause()
	if arena.paused:
		if Input.is_action_just_pressed("move_left"): Beat.cal -= 0.01
		if Input.is_action_just_pressed("move_right"): Beat.cal += 0.01
		if Input.is_action_just_pressed("ui_select_alt"):
			arena._toggle_pause()
			get_tree().reload_current_scene()
			return
	elif G.game_over:
		if banner_t <= 0:
			show_banner("K.O. — SELECT TO RETRY", 99.0)
		if Input.is_action_just_pressed("ui_select_alt"):
			get_tree().reload_current_scene()
			return
	if pause_panel.visible:
		_update_pause_text()
	draw.update()

func _bar(pos, size, frac, col, back = Color(0, 0, 0, 0.55)):
	draw.draw_rect(Rect2(pos - Vector2(2, 2), size + Vector2(4, 4)), back)
	draw.draw_rect(Rect2(pos, Vector2(size.x * clamp(frac, 0, 1), size.y)), col)

func _on_draw():
	var vs = draw.get_rect().size
	var cam = arena.cam_rig.cam
	# --- left: HP, Fever, stars
	_bar(Vector2(14, 14), Vector2(180, 10), G.hp / G.max_hp, Color(1, 0.3, 0.35))
	draw.draw_string(font_small, Vector2(16, 36), "SLEEZE", Color(1, 1, 1))
	var fc = Color(1, 0.25, 0.75) if not G.rushing() else Color(1, 0.82, 0.25).linear_interpolate(Color(1, 0.25, 0.75), Beat.phase())
	_bar(Vector2(14, 42), Vector2(140, 7), G.fever / 100.0, fc)
	draw.draw_string(font_small, Vector2(16, 62), "FEVER RUSH!" if G.rushing() else "FEVER", fc)
	var stars = ""
	for i in range(G.star_cap):
		stars += "★" if i < G.stars else "☆"
	draw.draw_string(font, Vector2(160, 54), stars, Color(1, 0.82, 0.25))
	# --- right: score, combo, rank
	var sc = "%07d" % G.score
	draw.draw_string(font, Vector2(vs.x - 14 - font.get_string_size(sc).x, 26), sc, Color(1, 1, 1))
	if G.combo > 1:
		var ct = "%d COMBO" % G.combo
		draw.draw_string(font, Vector2(vs.x - 14 - font.get_string_size(ct).x, 46), ct, Color(0.2, 0.95, 1))
	var rk = "RANK " + G.style_rank()
	draw.draw_string(font_small, Vector2(vs.x - 14 - font_small.get_string_size(rk).x, 62), rk, Color(1, 0.82, 0.25))
	# --- beat bar (bottom centre): 4 pips, downbeat bigger
	var cx = vs.x * 0.5
	var by = vs.y - 26
	var bf = Beat.beat_float()
	var cur = int(floor(bf))
	for k in range(4):
		var on = posmod(cur, 4) == k
		var r = 5.0 + (5.0 * beat_pulse if on else 0.0) + (2.0 if k == 0 else 0.0)
		var col = Color(1, 0.82, 0.25) if k == 0 else Color(0.2, 0.95, 1)
		col.a = 1.0 if on else 0.35
		draw.draw_circle(Vector2(cx - 45 + k * 30, by), r, col)
	draw.draw_string(font_small, Vector2(cx - 60, by + 18), "%s · %d BPM" % [Beat.SONG.name, int(Beat.bpm)], Color(1, 1, 1, 0.7))
	# --- enemy telegraphs: glowing ring + beat countdown over the attacker
	for e in arena.enemies:
		if e.dead:
			continue
		var head = e.global_transform.origin + Vector3.UP * 2.25
		if cam.is_position_behind(head):
			continue
		var sp = cam.unproject_position(head)
		var hpf = e.hp / e.max_hp
		if hpf < 1.0:
			draw.draw_rect(Rect2(sp + Vector2(-16, 10), Vector2(32, 3)), Color(0, 0, 0, 0.6))
			draw.draw_rect(Rect2(sp + Vector2(-16, 10), Vector2(32 * hpf, 3)), e.st.col)
		var n = e.beats_to_strike()
		if n >= 0:
			var ph = Beat.phase()
			var rr = 13.0 + 6.0 * (1.0 - ph)
			var c = Color(1, 0.2, 0.1) if n <= 1 else Color(1, 0.75, 0.2)
			draw.draw_arc(sp, rr + 3, 0, TAU, 24, Color(c.r, c.g, c.b, 0.35), 5.0)
			draw.draw_arc(sp, rr, 0, TAU, 24, c, 2.0)
			var txt = str(max(n, 1)) if n > 0 else "!"
			draw.draw_string(font, sp + Vector2(-font.get_string_size(txt).x * 0.5, 5), txt, Color(1, 1, 1))
			if n <= 1:
				draw.draw_string(font_small, sp + Vector2(-12, -rr - 6), "○ COUNTER", Color(1, 0.82, 0.25))
	# --- lock reticle
	var lt = arena.player.lock_target
	if lt and is_instance_valid(lt) and not lt.dead:
		var p3 = lt.global_transform.origin + Vector3.UP * 1.1
		if not cam.is_position_behind(p3):
			var sp2 = cam.unproject_position(p3)
			for a in range(4):
				var ang = a * PI * 0.5 + Beat.phase() * 0.6
				var d = Vector2(cos(ang), sin(ang))
				draw.draw_line(sp2 + d * 18, sp2 + d * 26, Color(1, 0.25, 0.75), 2.0)
	# --- judgement pops
	for p in pops:
		var pos3 = p.pos + Vector3.UP * p.t * 0.8
		if cam.is_position_behind(pos3):
			continue
		var s = cam.unproject_position(pos3)
		var c2 = p.color
		c2.a = clamp(1.4 - p.t * 1.5, 0, 1)
		var f = font if p.text.length() > 3 else font_big
		draw.draw_string(f, s - Vector2(f.get_string_size(p.text).x * 0.5, 0), p.text, c2)
	# --- banner
	if banner_t > 0:
		var a = clamp(banner_t * 2.0, 0, 1)
		var w = font_big.get_string_size(banner).x
		draw.draw_rect(Rect2(0, vs.y * 0.3 - 30, vs.x, 44), Color(0, 0, 0, 0.45 * a))
		draw.draw_string(font_big, Vector2(cx - w * 0.5, vs.y * 0.3), banner, Color(1, 0.82, 0.25, a))
	if show_fps:
		var info = "%d FPS · %d draws · %dk verts" % [Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.RENDER_DRAW_CALLS_IN_FRAME),
			int(Performance.get_monitor(Performance.RENDER_VERTICES_IN_FRAME) / 1000)]
		draw.draw_string(font_small, Vector2(14, vs.y - 8), info, Color(1, 1, 1, 0.6))
