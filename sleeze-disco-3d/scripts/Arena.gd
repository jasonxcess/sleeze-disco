extends Spatial
# SLEEZE DISCO — Beat Kune Do · 3D arena v0.2 PSX
# Builds the whole arena at runtime: the real 3D club (no backdrop), DJ riser +
# stage lip + steps, environment (neon depth fog, optional far DOF), the player,
# camera, waves of thugs + Vex, FX pools, crowd with distance LOD, HUD, pause.
# v0.2: PSX pipeline — plain AnimationPlayer (no AnimationTree), no
# SkeletonIK, no ragdoll, 480x272 internal viewport, 30 Hz physics.

const PlayerScript = preload("res://scripts/Player.gd")
const EnemyScript = preload("res://scripts/Enemy.gd")
const CameraRigScript = preload("res://scripts/CameraRig.gd")
const HUDScript = preload("res://scripts/HUD.gd")
const BotScript = preload("res://scripts/Bot.gd")

var player
var cam_rig
var hud
var env : Environment
var enemies = []
var tokens = []
var max_tokens = 1
var pulse = 0.0
var pulse_mats = []      # [material, base color]
var floor_mat : SpatialMaterial
var warm_cam : Camera  # v0.1.2: warm-up camera (see _ready) — freed at fighters stage
var disco : Spatial
var lod_items = []       # [node, max_dist, anim_player_or_null]
var _lod_t = 0.0
var sparks = []
var spark_i = 0
var dusts = []
var dust_i = 0
var sfx_players = []
var sfx_i = 0
var sounds = {}
var wave_queue = []
var spawn_t = 0.0
var between_waves = 2.0
var dof_auto_off = false
var _slow_frames = 0
var spawn_points = []
var stage_edge_x = -1.0
var paused = false
var ready_done = false

const WAVES = [
	["stan", "stan", "charger"],
	["stan", "charger", "bruiser", "stan"],
	["vex", "stan", "charger"],
]

const DiagScript = preload("res://scripts/Diag.gd")
var cfg = {}
var diag
var max_alive = 4

func _stage(name):
	G.blog("stage: " + name)
	if diag:
		diag.set_stage(name)

func _ready():
	randomize()
	G.reset_fight()
	cfg = G.cfg()
	max_alive = cfg.max_alive
	G.blog("Arena._ready profile=%s" % G.profile)
	diag = DiagScript.new()
	add_child(diag)
	# stage names are drawn BEFORE each heavy step, so a hang shows where it stopped
	_stage("start")
	yield(VisualServer, "frame_post_draw")
	_stage("club")
	yield(VisualServer, "frame_post_draw")
	_build_club()
	# let Bullet register the club collision before any ray probes
	yield(get_tree(), "physics_frame")
	yield(get_tree(), "physics_frame")
	_build_riser()
	# v0.1.2 SHADER WARM-UP: a plain camera that exists from the club stage
	# on, so the club's shaders compile on the nav stage's frame instead of
	# piling up on the first frame that has the player + environment (the
	# 167 s env frame on the Vita). No camera existed before the fighters
	# stage, so NOTHING compiled until the first 3D frame — every material
	# variant in the whole scene compiled at once. The warm-up camera looks
	# at the dance floor; the real chase rig replaces it at the fighters
	# stage. The fighters use the same unshaded variants the club already
	# compiled, so the env / present frames compile nothing new.
	warm_cam = Camera.new()
	warm_cam.fov = 62.0
	warm_cam.near = 0.15
	warm_cam.far = 60.0
	add_child(warm_cam)
	warm_cam.translation = Vector3(6.0, 4.0, 8.0)
	warm_cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	warm_cam.current = true
	if has_meta("nav_bake"):
		return
	_stage("nav")
	yield(VisualServer, "frame_post_draw")
	_build_nav()
	_build_floor_overlay()
	_stage("fx")
	yield(VisualServer, "frame_post_draw")
	_build_fx()
	if cfg.crowd:
		_stage("crowd")
		yield(VisualServer, "frame_post_draw")
		_build_crowd()
	_stage("fighters")
	yield(VisualServer, "frame_post_draw")
	player = PlayerScript.new()
	player.name = "Player"
	player.arena = self
	player.translation = Vector3(3.0, 0.05, 2.0)
	add_child(player)
	cam_rig = CameraRigScript.new()
	cam_rig.player = player
	add_child(cam_rig)
	player.cam_rig = cam_rig
	# warm-up camera's job is done — the chase rig's camera is current now
	if warm_cam:
		warm_cam.queue_free()
		warm_cam = null
	hud = HUDScript.new()
	hud.arena = self
	add_child(hud)
	Beat.connect("beat", self, "_on_beat")
	G.connect("flash", self, "flash")
	_stage("env")
	yield(VisualServer, "frame_post_draw")
	_build_environment()
	# present a few frames of the finished scene before the song starts,
	# so "music playing" proves the renderer is alive
	for i in range(5):
		_stage("present %d/5" % (i + 1))
		yield(VisualServer, "frame_post_draw")
	_stage("music")
	Beat.start()
	if G.bot:
		var b = BotScript.new()
		b.arena = self
		add_child(b)
	_next_wave()
	ready_done = true
	_stage("")
	diag.loaded()
	G.blog("Arena ready")

# ------------------------------------------------------------------ helpers
func find_type(n, cls):
	if n.get_class() == cls:
		return n
	for c in n.get_children():
		var r = find_type(c, cls)
		if r:
			return r
	return null

func _all_meshes(n, out):
	if n is MeshInstance:
		out.append(n)
	for c in n.get_children():
		_all_meshes(c, out)
	return out

func prep_character_materials(model, tint, energy):
	# v0.1.2: UNSHADED (was vertex-lit) + NO emission (was a tint glow).
	# Unshaded kills the lit shader variant — the 167 s env-frame compile
	# storm on the Vita. No emission kills the halo around the fighters
	# (glow post-FX is also off in every profile now). Identity tint is a
	# mild albedo tint instead (unshaded shows albedo directly). `energy`
	# is kept in the signature for the callers but ignored — no emission.
	var mats = []
	for mi in _all_meshes(model, []):
		for s in range(mi.get_surface_material_count()):
			var m = mi.mesh.surface_get_material(s)
			if m == null:
				continue
			m = m.duplicate()
			m.flags_unshaded = true
			m.metallic = 0.0
			m.roughness = 1.0
			m.emission_enabled = false
			m.emission_energy = 0.0
			m.albedo_color = Color(1, 1, 1).linear_interpolate(tint, 0.35)
			m.rim_enabled = false
			mi.set_surface_material(s, m)
			mats.append(m)
	return mats

var _blob_tex
func add_blob_shadow(body, size):
	if _blob_tex == null:
		_blob_tex = load("res://assets/fx/blob.png")
	var q = MeshInstance.new()
	var pm = QuadMesh.new(); pm.size = Vector2(size, size)
	q.mesh = pm
	q.rotation_degrees.x = -90
	q.translation.y = 0.03
	var m = SpatialMaterial.new()
	m.flags_unshaded = true
	m.flags_transparent = true
	m.albedo_texture = _blob_tex
	m.albedo_color = Color(0, 0, 0, 0.75)
	q.material_override = m
	q.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	body.add_child(q)

func ray_floor(x, z, from_y = 3.0):
	var hit = get_world().direct_space_state.intersect_ray(Vector3(x, from_y, z), Vector3(x, -3.0, z), [], G.L_WORLD)
	return hit.position.y if hit else null

# ------------------------------------------------------------------ environment
func _build_environment():
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.0, 0.06)
	env.ambient_light_color = Color(0.55, 0.42, 0.7)
	env.ambient_light_energy = 0.75
	env.fog_enabled = cfg.fog
	env.fog_color = Color(0.32, 0.06, 0.42)
	env.fog_sun_amount = 0.0
	env.fog_depth_enabled = cfg.fog
	env.fog_depth_begin = 9.0
	env.fog_depth_end = 42.0
	env.fog_depth_curve = 1.4
	env.fog_height_enabled = false
	env.glow_enabled = cfg.glow
	env.glow_intensity = 0.55
	env.glow_strength = 0.9
	env.glow_bloom = 0.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 0.85
	for i in range(1, 8):
		env.set("glow_levels/%d" % i, i == 2 or i == 3)
	# cheap background DOF: GLES2 in Godot 3.5 supports far blur; low quality.
	# Auto-disabled at runtime if the frame rate drops (see _process).
	env.dof_blur_far_enabled = cfg.dof
	env.dof_blur_far_distance = 16.0
	env.dof_blur_far_transition = 10.0
	env.dof_blur_far_amount = 0.06
	env.dof_blur_far_quality = Environment.DOF_BLUR_QUALITY_LOW
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we = WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# v0.1.2: NO scene lights. Every material in the game is unshaded now
	# (fighters, crowd, club, riser), so a DirectionalLight + OmniLight
	# lit nothing visible — but their presence forced the renderer to
	# compile the lit shader variant on the first frame that had them
	# (the present 1/5 stall on the Vita). The beat-reactive pink wash
	# they gave is replaced by the pulse_mats / floor_mat albedo pulse,
	# which is the same look with no light cost. key_light is gone too
	# (see _process).

# ------------------------------------------------------------------ club
func _build_club():
	var club = load("res://assets/models/club.glb").instance()
	club.name = "Club"
	# v0.1.2 SIMPLIFIED CLUB: strip the prop / small clutter meshes at load.
	# Before: 39 meshes / 75 prims / 15,165 tris. The props_* + small_* sets
	# are ~9,000 tris and ~25 meshes of edge clutter (tables, chairs, small
	# items) that the fight never touches. After: shell + disco + spotlights
	# only, ~6,100 tris / ~14 meshes / ~30 prims — the room, the dance
	# floor, the disco ball and the beams, which is the whole look. The
	# collision hull (club-colonly) and the navmesh are untouched, so the
	# old prop spots still read as blocked at the room edges; the dance
	# floor itself was always clear. No new asset: the Sketchfab
	# MozillaHubs "Nightclub" (2.5k tris, CC-BY) is the ideal replacement
	# but needs a Sketchfab login to download — flagged for a later round.
	var strip = []
	for mi in _all_meshes(club, []):
		var nm = mi.name.to_lower()
		if nm.begins_with("props") or nm.begins_with("small"):
			strip.append(mi)
	for mi in strip:
		mi.free()  # immediate: club is not in the tree yet, nothing references these
	add_child(club)
	var seen = {}
	for mi in _all_meshes(club, []):
		mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		var nm = mi.name.to_lower()
		if nm.begins_with("small"):
			lod_items.append([mi, 16.0, null])
		elif nm.begins_with("props"):
			lod_items.append([mi, 34.0, null])
		elif nm.begins_with("spot"):
			lod_items.append([mi, 60.0, null, 5.5])   # near-hide: never let a beam fill the lens
		elif nm.begins_with("disco"):
			disco = mi
			lod_items.append([mi, 80.0, null, 4.5])
		for s in range(mi.get_surface_material_count()):
			var m = mi.mesh.surface_get_material(s)
			if m == null or seen.has(m):
				continue
			seen[m] = true
			var n = m.resource_name.to_lower()
			# the club's textures are light-baked: render them unshaded (cheapest + truest)
			m.flags_unshaded = true
			m.params_specular_mode = SpatialMaterial.SPECULAR_DISABLED
			if n.begins_with("glass"):
				m.flags_transparent = true
				m.albedo_color = Color(0.1, 0.25, 0.6, 0.45)
			if n.begins_with("neon") or n.begins_with("tile") or n.begins_with("spotlight") or n.begins_with("discoaura") or n.begins_with("tvscreen"):
				pulse_mats.append([m, m.albedo_color])
			if n.begins_with("shell"):
				m.albedo_color = Color(0.13, 0.11, 0.17)
			if n.begins_with("spotlight"):
				# v0.1.2: distance fade REMOVED — it was its own shader
				# variant, and the LOD near-hide (spot beams hidden < 5.5 m)
				# already stops a beam filling the lens. Beams stay
				# transparent so they read as light.
				m.flags_transparent = true
	# collision: the importer turned "club-colonly" into a StaticBody
	var sb = find_type(club, "StaticBody")
	if sb:
		sb.collision_layer = G.L_WORLD
		sb.collision_mask = 0
	else:
		push_warning("club collision missing")

func _build_riser():
	# Find the front edge of the stage (pit floor is y=0, stage ~0.85) along z=0
	var x = 4.0
	stage_edge_x = -1.0
	while x > -10.0:
		var y = ray_floor(x, 0.0)
		if y != null and y > 0.4:
			stage_edge_x = x + 0.1
			break
		x -= 0.1
	var stage_y = ray_floor(stage_edge_x - 1.0, 0.0)
	if stage_y == null:
		stage_y = 0.85
	var neon = SpatialMaterial.new()
	neon.flags_unshaded = true
	neon.albedo_color = Color(1.0, 0.25, 0.75)
	pulse_mats.append([neon, neon.albedo_color])
	var dark = SpatialMaterial.new()
	dark.albedo_color = Color(0.09, 0.07, 0.12)
	dark.flags_unshaded = true  # v0.1.2: was vertex-lit; all materials unshaded now
	# stage lip (0.28) + step (0.56) in front of the stage, 4.4 m wide
	var steps = [[0.28, 0.75], [stage_y * 0.66, 0.6]]
	var xcur = stage_edge_x
	for s in steps:
		var h = s[0]; var d = s[1]
		_box(Vector3(xcur + d * 0.5, h * 0.5, 0), Vector3(d, h, 4.4), dark, true)
		_box(Vector3(xcur + d + 0.01, h - 0.02, 0), Vector3(0.04, 0.04, 4.4), neon, false)
		xcur += d
	# invisible ramps so the capsule walks up the steps (v0.2 PSX: no foot
	# IK — the baked walk cycle plants the feet; a foot may clip a step
	# slightly, which is how PS1 games looked)
	var ramp_len = xcur - stage_edge_x + 0.6
	var ramp = StaticBody.new()
	ramp.collision_layer = G.L_WORLD
	var rcs = CollisionShape.new()
	var rb = BoxShape.new(); rb.extents = Vector3(ramp_len * 0.5 / cos(atan2(stage_y, ramp_len)), 0.05, 2.2)
	rcs.shape = rb
	ramp.add_child(rcs)
	ramp.translation = Vector3(stage_edge_x + (xcur - stage_edge_x + 0.6) * 0.5 - 0.3, stage_y * 0.5 - 0.02, 0)
	ramp.rotation.z = atan2(stage_y, ramp_len)
	add_child(ramp)
	# DJ riser on the stage: 0.35 m block with a neon lip
	var rx = stage_edge_x - 3.0
	_box(Vector3(rx, stage_y + 0.175, 0), Vector3(1.6, 0.35, 3.0), dark, true)
	_box(Vector3(rx + 0.81, stage_y + 0.33, 0), Vector3(0.03, 0.03, 3.0), neon, false)

func _box(pos, size, mat, solid):
	var mi = MeshInstance.new()
	var cm = CubeMesh.new(); cm.size = size
	mi.mesh = cm
	mi.material_override = mat
	mi.translation = pos
	add_child(mi)
	if solid:
		var sb = StaticBody.new()
		sb.collision_layer = G.L_WORLD
		var cs = CollisionShape.new()
		var bs = BoxShape.new(); bs.extents = size * 0.5
		cs.shape = bs
		sb.add_child(cs)
		sb.translation = pos
		add_child(sb)

var nav : Navigation
func _build_nav():
	# navmesh baked offline by tools/bake_nav.gd (static colliders incl. ramp)
	var nm = load("res://data/arena_nav.tres") if ResourceLoader.exists("res://data/arena_nav.tres") else null
	if nm == null:
		push_warning("no navmesh: enemies steer directly")
		return
	nav = Navigation.new()
	nav.cell_size = 0.15
	nav.cell_height = 0.1
	add_child(nav)
	var nmi = NavigationMeshInstance.new()
	nmi.navmesh = nm
	nav.add_child(nmi)

func nav_path(from, to):
	if nav == null:
		return PoolVector3Array([to])
	var m = nav.get_rid()
	var a = NavigationServer.map_get_closest_point(m, from)
	var b = NavigationServer.map_get_closest_point(m, to)
	return NavigationServer.map_get_path(m, a, b, true)

func _build_floor_overlay():
	var mi = MeshInstance.new()
	var pm = PlaneMesh.new(); pm.size = Vector2(9.0, 13.0)
	mi.mesh = pm
	floor_mat = SpatialMaterial.new()
	floor_mat.flags_unshaded = true
	floor_mat.flags_transparent = true
	floor_mat.params_blend_mode = SpatialMaterial.BLEND_MODE_ADD
	floor_mat.albedo_texture = load("res://assets/fx/floor_grid.png")
	floor_mat.uv1_scale = Vector3(1.0, 13.0 / 9.0, 1.0)
	floor_mat.albedo_color = Color(0.2, 0.6, 1.0, 0.5)
	mi.material_override = floor_mat
	mi.translation = Vector3(stage_edge_x + 5.2, 0.015, 0.5)
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

# ------------------------------------------------------------------ FX
func _build_fx():
	var spark_tex = load("res://assets/fx/spark.png")
	var dust_tex = load("res://assets/fx/dust.png")
	for i in range(4):
		sparks.append(_particles(spark_tex, 14, 0.28, 6.0, Color(1, 0.85, 0.4), 0.18, true))
	for i in range(2):
		dusts.append(_particles(dust_tex, 8, 0.6, 1.6, Color(0.8, 0.7, 0.9, 0.6), 0.5, false))
	for f in ["impactPunch_heavy_000", "impactPunch_heavy_001", "impactPunch_heavy_002", "impactPunch_medium_000",
			"impactPunch_medium_001", "impactPunch_medium_002", "impactSoft_heavy_000", "footstep_concrete_000",
			"footstep_concrete_001", "footstep_concrete_002", "impactGeneric_light_000", "impactBell_heavy_000"]:
		sounds[f] = load("res://assets/sfx/%s.ogg" % f)
	for i in range(5):
		var p = AudioStreamPlayer.new()
		add_child(p)
		sfx_players.append(p)

func _particles(tex, amount, life, vel, col, scale, additive):
	var p = CPUParticles.new()
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.95
	p.local_coords = false
	var q = QuadMesh.new(); q.size = Vector2(scale, scale)
	var m = SpatialMaterial.new()
	m.flags_unshaded = true
	m.flags_transparent = true
	m.params_billboard_mode = SpatialMaterial.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	if additive:
		m.params_blend_mode = SpatialMaterial.BLEND_MODE_ADD
	q.material = m
	p.mesh = q
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity = vel
	p.initial_velocity_random = 0.5
	p.gravity = Vector3(0, -9.0 if additive else 0.5, 0)
	p.damping = 2.0
	p.scale_amount = 1.0
	p.scale_amount_random = 0.5
	p.color = col
	var g = Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = g
	add_child(p)
	return p

func spark(pos, col, n = 10):
	var p = sparks[spark_i % sparks.size()]
	spark_i += 1
	p.global_transform.origin = pos
	p.color = col
	p.amount = int(clamp(n, 4, 16))
	p.restart()
	p.emitting = true

func dust(pos):
	var p = dusts[dust_i % dusts.size()]
	dust_i += 1
	p.global_transform.origin = pos
	p.restart()
	p.emitting = true

func sfx(kind, at = null, db = -2.0):
	var pick = {
		"heavy": ["impactPunch_heavy_000", "impactPunch_heavy_001", "impactPunch_heavy_002"],
		"medium": ["impactPunch_medium_000", "impactPunch_medium_001", "impactPunch_medium_002"],
		"hurt": ["impactSoft_heavy_000"], "block": ["impactGeneric_light_000"], "ko": ["impactBell_heavy_000"],
		"step": ["footstep_concrete_000", "footstep_concrete_001", "footstep_concrete_002"]}[kind]
	var p = sfx_players[sfx_i % sfx_players.size()]
	sfx_i += 1
	p.stream = sounds[pick[randi() % pick.size()]]
	p.volume_db = db
	p.pitch_scale = rand_range(0.92, 1.08)
	p.play()

func popup(text, col, pos):
	hud.pop(text, col, pos)

func flash(strength):
	pulse = max(pulse, strength)

# ------------------------------------------------------------------ crowd + LOD
func _build_crowd():
	var spots = [Vector3(-7.5, 0, -11.6), Vector3(-1.0, 0, -11.8), Vector3(4.5, 0, -11.4),
		Vector3(-6.0, 0, 11.9), Vector3(0.5, 0, 12.0), Vector3(5.5, 0, 11.6)]
	var scene = load("res://assets/models/crowd.glb")
	var i = 0
	for s in spots:
		var y = ray_floor(s.x, s.z, 4.5)
		if y == null:
			continue
		var c = scene.instance()
		c.translation = Vector3(s.x, y, s.z)
		c.rotation.y = 0.0 if s.z < 0 else PI
		add_child(c)
		var ap = find_type(c, "AnimationPlayer")
		if ap and ap.has_animation("dance"):
			ap.get_animation("dance").loop = true
			ap.play("dance")
			ap.seek(fmod(i * 0.73, ap.current_animation_length), true)
			ap.playback_speed = Beat.SONG.bpm / 100.0
		for mi in _all_meshes(c, []):
			mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
			for k in range(mi.get_surface_material_count()):
				var m = mi.mesh.surface_get_material(k)
				if m:
					m = m.duplicate()
					# v0.1.2: unshaded + no emission (was vertex-lit + emissive).
					# Same reason as the fighters: kills the lit shader variant
					# and the halo. Identity is a mild albedo tint.
					m.flags_unshaded = true
					m.emission_enabled = false
					m.emission_energy = 0.0
					m.albedo_color = Color(1, 1, 1).linear_interpolate(Color(0.35, 0.3, 0.45), 0.5)
					mi.set_surface_material(k, m)
		lod_items.append([c, 22.0, ap])
		i += 1

func _update_lod():
	var cam = cam_rig.cam
	var cp = cam.global_transform.origin
	for it in lod_items:
		var n = it[0]
		if not is_instance_valid(n):
			continue
		var dd = n.global_transform.origin.distance_to(cp)
		var vis = dd < it[1] and (it.size() < 4 or dd > it[3])
		if n.visible != vis:
			n.visible = vis
			if it[2]:
				if vis: it[2].play()
				else: it[2].stop(false)
	# enemies far from camera skip foot-sync work
	for e in enemies:
		e.lod_far = e.global_transform.origin.distance_to(cp) > 25.0

# ------------------------------------------------------------------ beat-reactive club
func _on_beat(_i, downbeat):
	pulse = max(pulse, 1.0 if downbeat else 0.55)
	if G.rushing():
		pulse = 1.2

func _process(delta):
	if not ready_done:
		return
	var rd = G.real_delta(delta)
	pulse = max(0.0, pulse - rd * 3.0)
	var k = 0.45 + 0.55 * min(pulse, 1.0)
	var rush = G.rushing()
	var hue_shift = Beat.beat_float() * 0.08 if rush else 0.0
	for pm in pulse_mats:
		var c = pm[1]
		if rush:
			c = Color.from_hsv(fmod(c.h + hue_shift, 1.0), c.s, c.v)
		pm[0].albedo_color = Color(c.r * k, c.g * k, c.b * k, c.a)
	var fc = Color.from_hsv(fmod(0.55 + Beat.beat_float() * (0.12 if rush else 0.03), 1.0), 0.8, 1.0)
	floor_mat.albedo_color = Color(fc.r, fc.g, fc.b, 0.12 + 0.45 * min(pulse, 1.2))
	# v0.1.2: key_light removed with the scene lights (see _build_environment).
	if disco:
		disco.rotate_y(rd * 0.6)
	_lod_t -= rd
	if _lod_t <= 0:
		_lod_t = 0.25
		_update_lod()
	# adaptive DOF: drop it if the frame rate can't hold 30
	if env and env.dof_blur_far_enabled and Engine.get_frames_per_second() > 0 and Engine.get_frames_per_second() < 28 and not G.bot:
		_slow_frames += 1
		if _slow_frames > 180:
			env.dof_blur_far_enabled = false
			dof_auto_off = true
			print("[Arena] DOF auto-disabled (fps < 28)")
	else:
		_slow_frames = 0

func _physics_process(delta):
	if not ready_done or G.game_over:
		return
	# waves
	if wave_queue.size() > 0:
		spawn_t -= delta
		if spawn_t <= 0 and _alive() < max_alive:
			_spawn(wave_queue.pop_front())
			spawn_t = 0.9
	elif _alive() == 0:
		between_waves -= delta
		if between_waves <= 0:
			_next_wave()

func _toggle_pause():
	paused = not paused
	get_tree().paused = paused
	Beat.set_paused(paused)
	hud.set_paused(paused)

# ------------------------------------------------------------------ waves / enemies
func _alive():
	var n = 0
	for e in enemies:
		if not e.dead:
			n += 1
	return n

func _next_wave():
	if G.wave >= WAVES.size():
		G.wave = 0   # endless loop of the three waves
	wave_queue = WAVES[G.wave].duplicate()
	G.wave += 1
	max_tokens = 2 if wave_queue.has("vex") or G.wave > 2 else 1
	hud.show_banner("WAVE %d" % G.wave if not wave_queue.has("vex") else "VEX — THE FINAL TEST", 2.2)
	spawn_t = 1.2
	between_waves = 2.5

func _spawn(kind):
	if spawn_points.empty():
		for p in [Vector3(7.5, 0, -6.5), Vector3(7.5, 0, 6.5), Vector3(-6.0, 0, 6.0), Vector3(-6.0, 0, -6.0), Vector3(8.0, 0, 0.0)]:
			var y = ray_floor(p.x, p.z)
			if y != null and abs(y) < 0.3:
				spawn_points.append(Vector3(p.x, y + 0.05, p.z))
		if spawn_points.empty():
			spawn_points.append(Vector3(6, 0.05, 0))
	var pos = spawn_points[randi() % spawn_points.size()]
	if kind == "vex":
		pos = Vector3(stage_edge_x - 1.5, 1.2, 0.0)
	var e = EnemyScript.new()
	e.init(self, player, kind, pos)
	e.name = "Enemy_%s_%d" % [kind, randi() % 10000]
	add_child(e)
	enemies.append(e)
	if kind == "vex":
		hud.show_banner("VEX", 1.6)

func nearest_enemy(pos, maxd, dir):
	var best = null
	var bd = maxd
	for e in enemies:
		if e.dead:
			continue
		var d = e.global_transform.origin - pos
		d.y = 0
		var l = d.length()
		if dir != null and l > 0.1 and dir.dot(d / l) < -0.2:
			l += 4.0
		if l < bd:
			bd = l; best = e
	return best

func request_token(e):
	tokens = [] + tokens
	for t in tokens.duplicate():
		if not is_instance_valid(t) or t.dead:
			tokens.erase(t)
	if tokens.has(e):
		return true
	if tokens.size() < max_tokens:
		tokens.append(e)
		return true
	return false

func release_token(e):
	tokens.erase(e)

func on_enemy_ko(e):
	sfx("ko", null, -6.0)
	spark(e.global_transform.origin + Vector3.UP * 1.2, Color(1, 0.4, 0.8), 16)
	popup("K.O.", Color(1, 0.25, 0.75), e.global_transform.origin + Vector3.UP * 2.4)
	if _alive() == 0 and wave_queue.empty():
		# last enemy of the wave: hit sparks + a short time-dip
		G.time_dip(650, 0.3)
		flash(1.3)
		cam_rig.shake(0.4)

func remove_enemy(e):
	enemies.erase(e)
	tokens.erase(e)
	if player.lock_target == e:
		player.lock_target = null
		cam_rig.set_lock(null)
	e.queue_free()
