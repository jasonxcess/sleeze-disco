extends Node
# Scripted-input test driver (--bot). Plays the arena for G.test_frames
# frames: moves, free-flow attacks toward enemies, counters telegraphs,
# dashes, toggles lock-on, fires finishers, pauses once; then prints stats
# and quits. --shots writes screenshots to user://shots/.

var arena
var f = 0
var shot_frames = [90, 400, 700, 1000, 1300, 1700, 2100, 2500]
var lock_toggled = 0
var paused_once = false
var min_fps = 999
var draws_max = 0
var verts_max = 0
var errors = 0

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	var d = Directory.new()
	d.make_dir_recursive("user://shots")

func _physics_process(_delta):
	var p = arena.player
	if p == null or not arena.ready_done:
		return
	f += 1
	var inp = {"move": Vector2.ZERO, "punch": false, "kick": false, "parry": false, "dash": false,
		"dash_held": false, "lock": false, "finisher": false, "cam": Vector2.ZERO}
	var me = p.global_transform.origin
	var tgt = arena.nearest_enemy(me, 40.0, null)
	var threat = null
	for e in arena.enemies:
		if not e.dead and e.in_counter_window() and e.global_transform.origin.distance_to(me) < 3.3:
			threat = e
	if tgt:
		var d = tgt.global_transform.origin - me
		d.y = 0
		var cam_b = arena.cam_rig.yaw_basis()
		var local = Vector2(cam_b.x.dot(d.normalized()), cam_b.z.dot(d.normalized()))
		if d.length() > 2.2 or abs(tgt.global_transform.origin.y - me.y) > 0.45:
			# walk the navmesh like a player would find the steps
			var path = arena.nav_path(me, tgt.global_transform.origin)
			var nd = d
			if path.size() > 1:
				nd = path[1] - me
				nd.y = 0
				if nd.length() < 0.3 and path.size() > 2:
					nd = path[2] - me; nd.y = 0
			var nloc = Vector2(cam_b.x.dot(nd.normalized()), cam_b.z.dot(nd.normalized()))
			inp.move = nloc * (1.0 if d.length() > 5 else 0.6)
		elif f % 200 > 170:
			inp.move = Vector2(-local.y, local.x)   # strafe a little
		if threat and f % 3 == 0:
			inp.parry = true
		elif d.length() < 5.0 and (f % 22 == 0 or (Beat.nearest_offset() < 0.03 and f % 4 == 0 and randf() < 0.3)):
			inp.punch = true
			inp.move = local
		elif d.length() < 5.0 and f % 61 == 0:
			inp.kick = true
		if G.stars > 0 and f % 90 == 0:
			inp.finisher = true
	else:
		inp.move = Vector2(sin(f * 0.02), cos(f * 0.017))
	if f % 240 == 120:
		inp.dash = true
		inp.dash_held = true
	if f % 700 == 350 and lock_toggled < 6:
		inp.lock = true
		lock_toggled += 1
	if f % 500 > 440:
		inp.cam = Vector2(0.6, 0)
	p.input_override = inp
	# keep the bot alive for the full run
	if G.hp < 30:
		G.hp = 100
	if G.game_over:
		G.game_over = false
		G.hp = 100
	var fps = Engine.get_frames_per_second()
	if f > 120:
		min_fps = min(min_fps, fps)
	draws_max = max(draws_max, Performance.get_monitor(Performance.RENDER_DRAW_CALLS_IN_FRAME))
	verts_max = max(verts_max, Performance.get_monitor(Performance.RENDER_VERTICES_IN_FRAME))
	if f == 1500 and not paused_once:
		paused_once = true
		arena._toggle_pause()
		yield(get_tree().create_timer(0.3), "timeout")
		arena._toggle_pause()
	if G.shots and f in shot_frames:
		_shot()
	if f % 300 == 0:
		print("[bot] f=%d t=%.2f beat=%.2f fps=%d draws=%d verts=%d enemies=%d wave=%d hp=%d combo=%d stats=%s" % [f, Beat.t, Beat.beat_float(),
			fps, Performance.get_monitor(Performance.RENDER_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_VERTICES_IN_FRAME),
			arena._alive(), G.wave, G.hp, G.combo, str(G.stats)])
		var desc = "  ts=%.3f paused=%s player %s pos=%s act=%s atime=%.2f aname=%s" % [Engine.time_scale, str(get_tree().paused), p.state, str(p.global_transform.origin), str(p.act.get("phase", "")), p.anim.act_time, p.anim.act_name]
		for e in arena.enemies:
			desc += "\n  enemy %s %s dead=%s hp=%.0f pos=%s" % [e.kind, e.state, str(e.dead), e.hp, str(e.global_transform.origin)]
		print(desc)
	if f >= G.test_frames:
		print("[bot] DONE frames=%d score=%d max_combo=%d perfects=%d kos=%d stats=%s max_draws=%d max_verts=%d mem_static=%.1fMB" % [f, G.score, G.max_combo,
			G.perfects, G.kos, str(G.stats), draws_max, verts_max, OS.get_static_memory_usage() / 1048576.0])
		get_tree().quit()

func _shot():
	yield(VisualServer, "frame_post_draw")
	var img = get_viewport().get_texture().get_data()
	img.flip_y()
	img.save_png("user://shots/shot_%05d.png" % f)
	print("[bot] shot ", f)
