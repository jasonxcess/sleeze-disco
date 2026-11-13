extends KinematicBody
# Thugs (stan / charger / bruiser) and Vex (mini-boss).
# chase -> circle (wait for an attack token) -> telegraph (beat countdown,
# counter window) -> strike (contact lands ON a beat) -> recover.
# Hits: directional flinch clip + small physics push. KO: canned knockdown
# clip (v0.2 PSX — no ragdoll: the Bullet PhysicalBone path is gone).

const Anim = preload("res://scripts/Anim.gd")

const STATS = {
	"stan": {"hp": 35, "spd": 2.3, "dmg": 8, "col": Color(0.2, 0.95, 1.0), "name": "BOUNCER", "model": "thug", "armor": false},
	"charger": {"hp": 45, "spd": 3.6, "dmg": 14, "col": Color(1.0, 0.25, 0.2), "name": "RUSHER", "model": "thug", "armor": false},
	"bruiser": {"hp": 95, "spd": 1.7, "dmg": 18, "col": Color(0.62, 0.3, 1.0), "name": "HEAVY", "model": "thug", "armor": true},
	"vex": {"hp": 280, "spd": 2.6, "dmg": 16, "col": Color(1.0, 0.25, 0.75), "name": "VEX", "model": "vex", "armor": true}
}
var arena
var player
var kind = "stan"
var st
var model : Spatial
var skel : Skeleton
var anim
var meta
var mats = []
var hp = 35.0
var max_hp = 35.0
var dead = false
var state = "spawn"
var state_t = 0.0
var vel = Vector3.ZERO
var push = Vector3.ZERO
var facing = Vector3(0, 0, 1)
var strike = {}
var strike_tb = 0.0
var tele_beats = 2
var stun_t = 0.0
var flash_t = 0.0
var taunt_cd = 3.0
var orbit_sign = 1.0
var hurtbox : Area
var ko_t = 0.0
var combo_left = 0
var lod_far = false
var path = PoolVector3Array()
var path_i = 0
var path_t = 0.0

func init(_arena, _player, _kind, pos):
	arena = _arena; player = _player; kind = _kind
	st = STATS[kind]
	hp = st.hp; max_hp = st.hp
	translation = pos
	orbit_sign = 1.0 if randf() > 0.5 else -1.0

func _ready():
	collision_layer = G.L_ENEMY
	collision_mask = G.L_WORLD | G.L_PLAYER | G.L_ENEMY
	var cs = CollisionShape.new()
	var cap = CapsuleShape.new(); cap.radius = 0.33; cap.height = 1.05
	cs.shape = cap
	cs.rotation_degrees.x = 90
	cs.translation.y = 0.88
	add_child(cs)
	model = load("res://assets/models/%s.glb" % st.model).instance()
	model.name = "Model"
	add_child(model)
	skel = arena.find_type(model, "Skeleton")
	var ap = arena.find_type(model, "AnimationPlayer")
	meta = G.meta[st.model]
	anim = Anim.new()
	anim.setup(self, ap, [["idle", 0.0, ap.get_animation("idle").length], ["walk", meta.walk.speed, meta.walk.len],
		["run", meta.run.speed, meta.run.len]])
	mats = arena.prep_character_materials(model, st.col, 0.18)
	# hurtbox on the chest bone
	var ba = BoneAttachment.new()
	ba.bone_name = "chest" if st.model == "thug" else "spine.003"
	skel.add_child(ba)
	hurtbox = Area.new()
	hurtbox.collision_layer = G.L_HURTBOX
	hurtbox.collision_mask = 0
	hurtbox.monitoring = false
	hurtbox.set_meta("owner", self)
	var hc = CollisionShape.new()
	var hcap = CapsuleShape.new(); hcap.radius = 0.32; hcap.height = 0.6
	hc.shape = hcap
	hurtbox.add_child(hc)
	ba.add_child(hurtbox)
	arena.add_blob_shadow(self, 1.0)
	_set_state("spawn")

func _set_state(s):
	state = s; state_t = 0.0

# ------------------------------------------------------------------ main loop
func _physics_process(delta):
	if dead:
		_tick_dead(delta)
		return
	state_t += delta
	stun_t = max(0.0, stun_t - delta)
	taunt_cd -= delta
	var me = global_transform.origin
	var pp = player.global_transform.origin
	var to = pp - me
	to.y = 0
	var dist = to.length()
	var dirp = to / max(dist, 0.001)
	var move_dir = _steer(me, pp, dist, dirp, delta)
	var want = Vector3.ZERO
	var spd = st.spd
	match state:
		"spawn":
			want = move_dir * spd
			if dist < 6.0 or state_t > 2.5:
				_set_state("chase")
		"chase":
			want = move_dir * spd * (1.25 if dist > 6 else 1.0)
			facing = move_dir if move_dir.length() > 0.1 else dirp
			if dist < 4.2 and abs(pp.y - me.y) < 0.45:
				_set_state("circle")
		"circle":
			facing = dirp
			var tangent = Vector3(-dirp.z, 0, dirp.x) * orbit_sign
			var radial = (dist - 3.1) * 1.2
			want = (tangent * 0.9 + dirp * radial).normalized() * spd * 0.6
			if dist > 5.5 or not _clear_line_cached(me, pp) or abs(pp.y - me.y) > 0.45:
				_set_state("chase")
			elif arena.request_token(self):
				_begin_telegraph()
			elif taunt_cd < 0 and randf() < 0.01:
				taunt_cd = 6.0 + randf() * 4.0
				_set_state("taunt")
				anim.play("taunt", 0.0, 1.0, anim.clip_len("taunt"), 0.1, 0.2)
		"taunt":
			facing = dirp
			if not anim.playing() or state_t > 1.6:
				_set_state("circle")
		"tele":
			facing = dirp
			var reach = meta[strike.clip].reach + 0.5
			if dist > reach:
				want = dirp * min(spd * 1.4, (dist - reach) * 4.0)
			# start the strike clip so its contact frame lands on strike_tb
			var seg = strike.contact - strike.start
			if Beat.t >= strike_tb - seg and not strike.started:
				strike.started = true
				anim.play(strike.clip, strike.start, 1.0, min(anim.clip_len(strike.clip), strike.contact + 0.5), 0.06, 0.2)
			if Beat.t >= strike_tb:
				_resolve_strike(dist, dirp)
		"recover":
			facing = dirp
			if state_t > 0.55:
				if combo_left > 0:
					combo_left -= 1
					_begin_telegraph(true)
				else:
					arena.release_token(self)
					_set_state("circle")
		"stun", "flinch":
			if stun_t <= 0 and state_t > 0.35:
				_set_state("circle")
	# separation from other enemies
	for o in arena.enemies:
		if o == self or o.dead:
			continue
		var d = me - o.global_transform.origin
		d.y = 0
		var l = d.length()
		if l < 1.3 and l > 0.001:
			want += d / l * (1.3 - l) * 3.0
	var hv = Vector3(vel.x, 0, vel.z)
	hv = hv.move_toward(want, 14.0 * delta)
	push = push.move_toward(Vector3.ZERO, 9.0 * delta)
	vel.x = hv.x; vel.z = hv.z
	vel.y = -2.0 if is_on_floor() else vel.y - 22.0 * delta
	move_and_slide_with_snap(vel + push, Vector3.DOWN * 0.4, Vector3.UP, true, 4, deg2rad(50))
	model.rotation.y = lerp_angle(model.rotation.y, atan2(facing.x, facing.z), min(1.0, 10 * delta))
	var ground_speed = Vector2(vel.x, vel.z).length()
	if lod_far:
		ground_speed = 0.0
	anim.update_loco(ground_speed, delta)
	anim.update(delta)
	_tick_tint(delta)

# ------------------------------------------------------------------ navigation
func _clear_line(a, b):
	var hit = get_world().direct_space_state.intersect_ray(a + Vector3.UP * 0.5, b + Vector3.UP * 0.5, [self, player], G.L_WORLD)
	return hit.empty()

func _steer(me, pp, dist, dirp, delta):
	# straight at the player when the line is clear; otherwise follow the navmesh
	path_t -= delta
	if (dist < 3.0 and abs(pp.y - me.y) < 0.45) or (_clear_line_cached(me, pp) and abs(pp.y - me.y) < 0.45):
		return dirp
	if path_t <= 0 or path_i >= path.size():
		path = arena.nav_path(me, pp)
		path_i = 1 if path.size() > 1 else 0
		path_t = 0.5
	while path_i < path.size():
		var w = path[path_i] - me
		w.y = 0
		if w.length() < 0.45:
			path_i += 1
			continue
		return w.normalized()
	return dirp

var _clear_cache = true
var _clear_t = 0.0
func _clear_line_cached(me, pp):
	_clear_t -= 1
	if _clear_t <= 0:
		_clear_t = 6
		_clear_cache = _clear_line(me, pp)
	return _clear_cache

# ------------------------------------------------------------------ attacking
func _begin_telegraph(chain = false):
	var clips = ["jab", "cross", "kick"] if st.model == "thug" else ["jab", "kick", "meialua"]
	if kind == "bruiser":
		clips = ["cross", "kick"]
	var c = clips[randi() % clips.size()]
	if kind == "vex" and not chain:
		combo_left = 1 if randf() < 0.6 else 0
	var m = meta[c]
	strike = {"clip": c, "contact": m.contact, "start": max(0.0, m.contact - 0.42), "started": false}
	# countdown: 2 beats (1 beat for a chained follow-up), strike lands on the beat
	tele_beats = 1 if chain else 2
	var first = Beat.next_beat_after(Beat.t + 0.15)
	strike_tb = first + Beat.spb * (tele_beats - 1)
	_set_state("tele")

func in_counter_window():
	return state == "tele" and Beat.t < strike_tb + 0.05

func beats_to_strike():
	if state != "tele":
		return -1
	return int(ceil((strike_tb - Beat.t) / Beat.spb - 0.001))

func _resolve_strike(dist, dirp):
	var reach = meta[strike.clip].reach + 0.75
	var p_to_me = -dirp
	var front = facing.dot(dirp) > 0.4
	if dist <= reach and front and not player.state == "down":
		player.take_hit(st.dmg, dirp, self)
	if state == "tele":
		_set_state("recover")

func countered():
	# ○ in the telegraph window: strike cancelled, 1.6 s stun
	arena.release_token(self)
	combo_left = 0
	anim.stop(0.08)
	stun_t = 1.6
	_set_state("stun")

func on_parried_by_player():
	arena.release_token(self)
	combo_left = 0
	stun_t = Beat.spb
	_set_state("stun")

# ------------------------------------------------------------------ taking hits
func take_hit(dmg, dir, heavy, finisher):
	if dead:
		return
	hp -= dmg
	flash_t = 0.1
	var armored = st.armor and state == "tele" and not finisher and not heavy
	if hp <= 0:
		_ko(dir, finisher)
		return
	if armored:
		push += dir * 0.8
		return
	if state == "tele" or state == "recover":
		arena.release_token(self)
		combo_left = 0
	var local = model.global_transform.basis.xform_inv(-dir)
	var clip = "hit_front"
	if local.z < -0.5:
		clip = "hit_back"
	elif abs(local.x) > abs(local.z):
		clip = "hit_head_l" if local.x > 0 else "hit_head_r"
	anim.play(clip, 0.0, 1.45 if not heavy else 1.15, min(anim.clip_len(clip), 0.8), 0.03, 0.2)
	push += dir * (3.4 if heavy else 2.0)
	stun_t = 0.45 if heavy else 0.3
	_set_state("flinch")

func _ko(dir, finisher):
	dead = true
	G.kos += 1
	G.stats.kos += 1
	G.add_fever(G.FEVER.KO)
	G.gain_score(100)
	arena.release_token(self)
	arena.on_enemy_ko(self)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", G.L_WORLD)
	if hurtbox:
		hurtbox.set_deferred("monitorable", false)
	ko_t = 0.0
	# v0.2 PSX: every KO is the canned knockdown clip. The old ragdoll
	# branch (runtime PhysicalBones + physical_bones_start_simulation) is
	# gone — it was the leading candidate for the v0.1.2 C2-12828-1 crash
	# on the Vita (runtime skeleton bound-node mutation; the code comments
	# already warned the bind could error), and the dump is the only proof.
	anim.play("knockdown", 0.4, 1.25, anim.clip_len("knockdown"), 0.04, 0.01)
	push = dir * (4.0 if finisher else 2.5)

func _tick_dead(delta):
	ko_t += delta
	push = push.move_toward(Vector3.ZERO, 6 * delta)
	move_and_slide(push + Vector3.DOWN * 2.0, Vector3.UP)
	if anim.act_time > anim.clip_len("knockdown") - 0.1:
		anim.act_time = anim.clip_len("knockdown") - 0.12
	anim.update_loco(0.0, delta)
	anim.update(delta)
	if ko_t > 2.6:
		model.translation.y -= delta * 0.8   # sink out through the floor
	if ko_t > 3.8:
		arena.remove_enemy(self)

# ------------------------------------------------------------------ readability tint
func _tick_tint(delta):
	# v0.1.2: telegraph / hit-flash signals moved from EMISSION to ALBEDO.
	# Emission is gone from every character material (it haloed the
	# fighters under glow post-FX, and glow is off in all profiles now).
	# Unshaded materials show albedo directly, so the cue reads the same
	# with no glow: base = mild type tint, telegraph = red pulse that
	# deepens as the beat approaches, hit = white flash.
	flash_t = max(0.0, flash_t - delta)
	var base = Color(1, 1, 1).linear_interpolate(st.col, 0.35)
	var c = base
	if state == "tele":
		var ph = Beat.phase()
		c = base.linear_interpolate(Color(1.0, 0.15, 0.1), 0.5 + 0.5 * (1.0 - ph))
	if flash_t > 0:
		c = Color(1, 1, 1)
	for m in mats:
		m.albedo_color = c
