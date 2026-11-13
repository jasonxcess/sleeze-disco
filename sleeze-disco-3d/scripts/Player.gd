extends KinematicBody
# Sleeze. KinematicBody with accel/decel, stride-matched locomotion, beat-snapped
# free-flow attacks with gap-close, bone-attached Area hitboxes, parry/counter,
# dash (sprint burst with lean + FOV kick), finisher.
# v0.2 PSX: no SkeletonIK — feet plant via the baked walk/run cycle
# (AnimationPlayer rate = speed / natural speed), not IK solves. The stage
# ramps are still collision (the capsule walks up them); feet may clip a
# step slightly, PSX-style. No ragdoll: KO is the canned knockdown clip.

const Anim = preload("res://scripts/Anim.gd")

const WALK_MAX = 2.0
const RUN_MAX = 5.0
const SPRINT = 8.2
const ACCEL = 22.0
const DECEL = 26.0
const TURN = 12.0
const GRAV = 22.0
const BODY_R = 0.32

var arena
var cam_rig
var model : Spatial
var skel : Skeleton
var anim
var meta = {}
var vel = Vector3.ZERO
var facing = Vector3(0, 0, -1)
var speed = 0.0
var on_floor = true

# action state
var state = "free"        # free | attack | parry | dash | hurt | down
var act = {}              # current attack data
var punch_n = 0
var parry_t = 0.0
var parry_cd = 0.0
var parry_judge = null
var dash_t = 0.0
var dash_cd = 0.0
var iframe_t = 0.0
var hurt_t = 0.0
var lunge = Vector3.ZERO
var lunge_t = 0.0
var lean = 0.0
var queued = ""
var lock_target = null
var hitboxes = {}
var _step_phase = 0.0
var input_override = null   # bot sets a Dictionary of fake input here

func _ready():
	collision_layer = G.L_PLAYER
	collision_mask = G.L_WORLD | G.L_ENEMY
	var cs = CollisionShape.new()
	var cap = CapsuleShape.new(); cap.radius = BODY_R; cap.height = 1.05
	cs.shape = cap
	cs.rotation_degrees.x = 90
	cs.translation.y = 0.85
	add_child(cs)
	model = load("res://assets/models/player.glb").instance()
	model.name = "Model"
	add_child(model)
	skel = arena.find_type(model, "Skeleton")
	var ap = arena.find_type(model, "AnimationPlayer")
	meta = G.meta.player
	anim = Anim.new()
	anim.setup(self, ap, [["idle", 0.0, anim_len(ap, "idle")], ["walk", meta.walk.speed, meta.walk.len],
		["run", meta.run.speed, meta.run.len], ["sprint", meta.sprint.speed, meta.sprint.len]])
	arena.prep_character_materials(model, Color(1, 0.8, 0.3), 0.0)
	_make_hitboxes()
	arena.add_blob_shadow(self, 0.9)

func anim_len(ap, n):
	return ap.get_animation(n).length if ap.has_animation(n) else 1.0

# ------------------------------------------------------------------ setup helpers
func _make_hitboxes():
	for pair in [["lh", "LeftHand"], ["rh", "RightHand"], ["lf", "LeftToeBase"], ["rf", "RightToeBase"]]:
		var ba = BoneAttachment.new()
		ba.bone_name = pair[1]
		skel.add_child(ba)
		var ar = Area.new()
		ar.collision_layer = G.L_HITBOX
		ar.collision_mask = G.L_HURTBOX
		ar.monitorable = false
		ar.monitoring = false
		var cs = CollisionShape.new()
		var sp = SphereShape.new(); sp.radius = 0.2
		cs.shape = sp
		ar.add_child(cs)
		ba.add_child(ar)
		ar.connect("area_entered", self, "_on_hitbox", [pair[0]])
		hitboxes[pair[0]] = ar

# ------------------------------------------------------------------ input
func _inp():
	if input_override != null:
		return input_override
	var mv = Vector2(Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up"))
	return {"move": mv,
		"punch": Input.is_action_just_pressed("punch"), "kick": Input.is_action_just_pressed("kick"),
		"parry": Input.is_action_just_pressed("parry"), "dash": Input.is_action_just_pressed("dash"),
		"dash_held": Input.is_action_pressed("dash"),
		"lock": Input.is_action_just_pressed("lock"), "finisher": Input.is_action_just_pressed("finisher")}

func _cam_dir(mv):
	if mv.length() < 0.1:
		return Vector3.ZERO
	var b = cam_rig.yaw_basis()
	var d = b.x * mv.x + b.z * mv.y
	d.y = 0
	return d.normalized() * min(1.0, mv.length())

# ------------------------------------------------------------------ main loop
func _physics_process(delta):
	if G.game_over and state != "down":
		_go_down()
	var i = _inp()
	var wish = _cam_dir(i.move)
	parry_cd = max(0.0, parry_cd - delta)
	dash_cd = max(0.0, dash_cd - delta)
	iframe_t = max(0.0, iframe_t - delta)
	if i.lock:
		_toggle_lock()
	if lock_target and (not is_instance_valid(lock_target) or lock_target.dead):
		lock_target = arena.nearest_enemy(global_transform.origin, 12.0, null)
		cam_rig.set_lock(lock_target)
	if state != "down":
		if i.punch: _press_attack("punch", wish)
		elif i.kick: _press_attack("kick", wish)
		elif i.finisher: _press_attack("finisher", wish)
		if i.parry: _press_parry()
		if i.dash: _press_dash(wish)
	match state:
		"free": _move_free(wish, i, delta)
		"attack": _tick_attack(delta)
		"parry": _tick_parry(delta, wish)
		"dash": _tick_dash(delta, wish, i)
		"hurt": _tick_hurt(delta)
		"down": _tick_down(delta)
	# gravity + move
	if not on_floor:
		vel.y -= GRAV * delta
	else:
		vel.y = -2.0
	var v = vel
	if lunge_t > 0:
		v += lunge
		lunge_t -= delta
	v = move_and_slide_with_snap(v, Vector3.DOWN * 0.4, Vector3.UP, true, 4, deg2rad(50))
	on_floor = is_on_floor()
	speed = Vector2(v.x, v.z).length()
	# facing + lean
	var yaw = atan2(facing.x, facing.z)
	model.rotation.y = lerp_angle(model.rotation.y, yaw, min(1.0, TURN * delta))
	var lean_target = 0.0
	if state == "dash":
		lean_target = 0.28
	elif state == "free":
		lean_target = clamp(speed / SPRINT, 0, 1) * 0.12
	lean = lerp(lean, lean_target, min(1.0, 10 * delta))
	model.rotation.x = lean
	anim.update_loco(Vector2(vel.x, vel.z).length() if state != "attack" else 0.0, delta)
	anim.update(delta)
	_footsteps(delta)

func _move_free(wish, i, delta):
	var target_speed = RUN_MAX * wish.length()
	if wish.length() < 0.55:
		target_speed = WALK_MAX * wish.length() / 0.55
	if i.dash_held and wish.length() > 0.5 and dash_cd < 0.3:
		target_speed = SPRINT * 0.85   # holding ✕ after the burst keeps a sprint
	var hv = Vector3(vel.x, 0, vel.z)
	var tv = wish.normalized() * target_speed if wish.length() > 0.01 else Vector3.ZERO
	var rate = ACCEL if tv.length() > hv.length() else DECEL
	hv = hv.move_toward(tv, rate * delta)
	vel.x = hv.x; vel.z = hv.z
	if hv.length() > 0.2:
		facing = hv.normalized()
	if lock_target and is_instance_valid(lock_target) and hv.length() < 0.5:
		var d = lock_target.global_transform.origin - global_transform.origin
		d.y = 0
		if d.length() > 0.1:
			facing = facing.linear_interpolate(d.normalized(), min(1.0, 6 * delta)).normalized()

# ------------------------------------------------------------------ attacks
func _pick_target(wish):
	var me = global_transform.origin
	var dir = wish if wish.length() > 0.2 else Vector3.ZERO
	if lock_target and is_instance_valid(lock_target) and not lock_target.dead and dir == Vector3.ZERO:
		return lock_target
	var best = null
	var best_score = 1e9
	for e in arena.enemies:
		if e.dead:
			continue
		var d = e.global_transform.origin - me
		d.y = 0
		var dist = d.length()
		if dist > 7.5:
			continue
		var sc = dist
		if dir != Vector3.ZERO:
			var ang = acos(clamp(dir.normalized().dot(d.normalized()), -1, 1))
			if ang > deg2rad(70):
				continue
			sc = dist * 0.35 + ang * 3.0
		elif dist > 4.0:
			# no stick: prefer what is in front
			var ang2 = acos(clamp(facing.dot(d.normalized()), -1, 1))
			sc += ang2 * 2.0
		if sc < best_score:
			best_score = sc; best = e
	return best

func _press_attack(kind, wish):
	if state == "down" or state == "hurt":
		return
	if state == "attack" and act.get("phase", "") != "recover":
		queued = kind   # buffered, fires on the following beat
		return
	_start_attack(kind, wish)

func _start_attack(kind, wish):
	if kind == "finisher":
		if G.stars <= 0:
			arena.popup("NO ★", G.COL.grey, global_transform.origin + Vector3.UP * 2.2)
			return
		G.stars -= 1
	var off = Beat.nearest_offset()
	var j = G.judge_offset(off)
	var clip = "jab"
	if kind == "punch":
		punch_n += 1
		clip = "uppercut" if punch_n % 3 == 0 else ("jab" if punch_n % 2 == 1 else "cross")
	elif kind == "kick":
		clip = "kick"
	elif kind == "finisher":
		clip = "spinflip" if G.stats.finishers % 2 == 0 else "meialua"
	var m = meta[clip]
	var contact = m.contact
	var windup = 0.36 if kind != "finisher" else 0.5
	var start = max(0.0, contact - windup)
	var seg = contact - start
	var rush = 1.3 if G.rushing() else 1.0
	# strike lands ON the next beat: pick the beat, then time-scale the clip so its contact frame hits it
	var tb = Beat.next_beat_after(Beat.t + seg / (2.2 * rush))
	var dt = tb - Beat.t
	var rate = clamp(seg / max(dt, 0.01), 0.55, 2.4)
	var target = _pick_target(wish)
	var reach = m.reach + 0.45
	if target:
		var d = target.global_transform.origin - global_transform.origin
		d.y = 0
		facing = d.normalized()
		var gap = d.length() - reach
		if gap > 0.05:
			# Arkham-style gap close: arrive exactly at reach on the contact beat
			lunge = facing * min(gap / max(dt, 0.08), 16.0)
			lunge_t = min(dt, gap / 4.0 + 0.05)
	elif wish.length() > 0.2:
		facing = wish.normalized()
	vel.x *= 0.2; vel.z *= 0.2
	var active = m.active
	act = {"kind": kind, "clip": clip, "judge": j, "target": target, "hit": {}, "start": start,
		"contact": contact, "a0": active[0], "a1": active[1], "limb": m.limb, "rate": rate,
		"phase": "windup", "tb": tb, "landed": false}
	var end_t = min(anim.clip_len(clip), active[1] + 0.45)
	anim.play(clip, start, rate, end_t, 0.05, 0.18)
	state = "attack"
	if kind == "finisher":
		cam_rig.kick_fov(8.0)
		arena.flash(1.0)

func _tick_attack(delta):
	vel.x = move_toward(vel.x, 0, DECEL * delta)
	vel.z = move_toward(vel.z, 0, DECEL * delta)
	var t = anim.act_time
	var hb = hitboxes[act.limb]
	if act.phase == "windup" and t >= act.a0:
		act.phase = "active"
		hb.set_deferred("monitoring", true)
		_fallback_contact_check(hb)
	if act.phase == "active":
		if t >= act.contact and not act.landed:
			_fallback_contact_check(hb)
			# a counter is a guaranteed connect on the countered enemy (it is stunned in place)
			var tg = act.get("target")
			if act.kind == "counter" and not act.landed and tg and is_instance_valid(tg) and not tg.dead \
					and tg.global_transform.origin.distance_to(global_transform.origin) < 4.0:
				_apply_hit(tg)
		if t >= act.a1:
			act.phase = "recover"
			hb.set_deferred("monitoring", false)
			if not act.landed:
				_fallback_contact_check(hb, true)
	if act.phase == "recover":
		if queued != "":
			var q = queued; queued = ""
			_start_attack(q, _cam_dir(_inp().move))
			return
		if not anim.playing() or t >= act.a1 + 0.3:
			state = "free"
			if anim.playing(): anim.stop(0.2)

func _fallback_contact_check(hb, last_chance = false):
	# Area overlap is the primary contact. This catches a strike whose bone
	# path grazes past a moving target at low frame rates, so a punch that
	# visibly reaches the body always connects.
	var me = global_transform.origin
	var p = hb.global_transform.origin
	for e in arena.enemies:
		if e.dead or act.hit.has(e):
			continue
		var c = e.global_transform.origin + Vector3.UP * 1.1
		var d = (p - c)
		var horiz = Vector2(d.x, d.z).length()
		var to = e.global_transform.origin - me
		to.y = 0
		var in_front = facing.dot(to.normalized()) > 0.3
		var lim = 0.55 if not last_chance else 0.75
		if act.kind == "finisher":
			if to.length() < 3.6:
				_apply_hit(e)
		elif horiz < lim and in_front and abs(d.y) < 0.9:
			_apply_hit(e)

func _on_hitbox(area, limb):
	if state != "attack" or act.get("phase", "") != "active" or limb != act.limb:
		return
	var e = area.get_meta("owner") if area.has_meta("owner") else null
	if e and not e.dead and not act.hit.has(e):
		_apply_hit(e)

func _apply_hit(e):
	act.hit[e] = true
	act.landed = true
	var j = act.judge
	var dmg = G.DMG.get(act.kind, 11)
	if act.kind == "punch" and act.clip == "uppercut":
		dmg = 14
	var mult = j.mult
	var heavy = act.kind != "punch" or act.clip == "uppercut" or j.name == "PERFECT!"
	var dir = e.global_transform.origin - global_transform.origin
	dir.y = 0
	dir = dir.normalized()
	var finisher = act.kind == "finisher"
	e.take_hit(dmg * mult, dir, heavy, finisher)
	G.landed(j, act.kind, not finisher)
	G.stats.hits += 1
	if finisher:
		G.stats.finishers += 1
	var hp = e.global_transform.origin + Vector3.UP * 1.3
	arena.spark(hp, j.color, 16 if j.name == "PERFECT!" else 9)
	arena.popup(j.name, j.color, hp + Vector3.UP * 0.6)
	arena.sfx("heavy" if heavy else "medium")
	G.hit_stop(80 if (heavy or finisher) else 40)
	if finisher:
		G.hit_stop(150)
	cam_rig.shake(0.35 if heavy else 0.15)
	if j.name == "PERFECT!":
		arena.flash(0.9)

# ------------------------------------------------------------------ parry / counter
func _press_parry():
	if state == "down" or state == "hurt" or parry_cd > 0:
		return
	parry_judge = G.judge_parry(Beat.nearest_offset())
	G.style_moves["parry"] = true
	# COUNTER: an enemy in its telegraph window within 3.4 m eats it now
	var me = global_transform.origin
	var best = null
	var bd = 3.4
	for e in arena.enemies:
		if e.dead or not e.in_counter_window():
			continue
		var d = e.global_transform.origin.distance_to(me)
		if d < bd:
			bd = d; best = e
	parry_cd = 2.0 * Beat.spb
	if best:
		var d2 = best.global_transform.origin - me
		d2.y = 0
		facing = d2.normalized()
		best.countered()
		G.style_moves["counter"] = true
		G.style += 4
		G.stats.counters += 1
		var j = {"name": "COUNTER", "mult": 1.0, "color": G.COL.gold}
		act = {"kind": "counter", "clip": "uppercut", "judge": j, "target": best, "hit": {}, "start": 0.15,
			"contact": meta.uppercut.contact, "a0": meta.uppercut.active[0] - 0.05, "a1": meta.uppercut.active[1] + 0.05,
			"limb": meta.uppercut.limb, "rate": 1.6, "phase": "windup", "landed": false}
		var gap = d2.length() - (meta.uppercut.reach + 0.45)
		if gap > 0.05:
			lunge = facing * min(gap / 0.12, 16.0); lunge_t = 0.12
		anim.play("uppercut", 0.15, 1.6, meta.uppercut.active[1] + 0.4, 0.04, 0.18)
		state = "attack"
		arena.popup("COUNTER!", G.COL.gold, best.global_transform.origin + Vector3.UP * 2.3)
		cam_rig.shake(0.3)
		return
	state = "parry"
	parry_t = 0.38
	iframe_t = 0.0
	anim.play("block", max(0.0, meta.block.contact - 0.25), 1.4, meta.block.contact + 0.2, 0.04, 0.14)
	arena.popup("PARRY " + parry_judge.name, parry_judge.color, global_transform.origin + Vector3.UP * 2.2)

func _tick_parry(delta, wish):
	parry_t -= delta
	vel.x = move_toward(vel.x, 0, DECEL * delta)
	vel.z = move_toward(vel.z, 0, DECEL * delta)
	if parry_t <= 0:
		state = "free"

func is_parrying():
	return state == "parry" and parry_t > 0

func on_parried(e):
	# called by an enemy whose strike met the parry
	G.stats.parries += 1
	if e and is_instance_valid(e) and e.has_method("on_parried_by_player"):
		e.on_parried_by_player()
	var good = parry_judge and parry_judge.name != "MISS"
	G.add_fever(G.FEVER.PARRY if good else G.FEVER.PARRY_OFF)
	G.gain_score(200 if good else 20)
	G.style += 2
	arena.spark(e.global_transform.origin + Vector3.UP * 1.4, G.COL.gold, 10)
	arena.sfx("block")
	G.hit_stop(60)
	cam_rig.shake(0.2)

# ------------------------------------------------------------------ dash
func _press_dash(wish):
	if dash_cd > 0 or state in ["down", "hurt"]:
		return
	if state == "attack" and act.get("phase", "") != "recover":
		return
	var d = wish if wish.length() > 0.2 else facing
	d = d.normalized()
	facing = d
	state = "dash"
	dash_t = 0.34
	dash_cd = 0.55
	iframe_t = 0.26
	vel.x = d.x * SPRINT * 1.25
	vel.z = d.z * SPRINT * 1.25
	cam_rig.kick_fov(11.0)
	arena.dust(global_transform.origin + Vector3.UP * 0.1)
	G.style_moves["dodge"] = true
	if anim.playing():
		anim.stop(0.08)

func _tick_dash(delta, wish, i):
	dash_t -= delta
	if wish.length() > 0.2:
		var hv = Vector3(vel.x, 0, vel.z)
		var steer = hv.length() * wish.normalized()
		hv = hv.linear_interpolate(steer, min(1.0, 5 * delta))
		vel.x = hv.x; vel.z = hv.z
		facing = hv.normalized()
	if dash_t <= 0:
		state = "free"
		var hv2 = Vector3(vel.x, 0, vel.z)
		var keep = SPRINT * 0.85 if i.dash_held else RUN_MAX
		if hv2.length() > keep:
			hv2 = hv2.normalized() * keep
		vel.x = hv2.x; vel.z = hv2.z

# ------------------------------------------------------------------ getting hit
func take_hit(dmg, from_dir, attacker):
	if state == "down" or iframe_t > 0:
		return false
	if is_parrying():
		on_parried(attacker)
		return false
	G.player_hurt(dmg)
	state = "hurt"
	hurt_t = 0.42
	iframe_t = 0.5
	var local = model.global_transform.basis.xform_inv(-from_dir)
	var clip = _flinch_clip(local)
	anim.play(clip, 0.0, 1.3, min(anim.clip_len(clip), 0.75), 0.04, 0.2)
	vel += from_dir * 3.0
	cam_rig.shake(0.45)
	arena.spark(global_transform.origin + Vector3.UP * 1.3, G.COL.red, 10)
	arena.sfx("hurt")
	arena.popup("-%d" % int(dmg), G.COL.red, global_transform.origin + Vector3.UP * 2.1)
	if G.hp <= 0:
		G.game_over = true
	return true

func _flinch_clip(local_dir):
	# local_dir: where the hit came FROM in model space (+Z = front)
	if local_dir.z > 0.5:
		return "hit_front"
	if local_dir.z < -0.5:
		return "hit_back"
	return "hit_head_l" if local_dir.x > 0 else "hit_head_r"

func _tick_hurt(delta):
	hurt_t -= delta
	vel.x = move_toward(vel.x, 0, 10 * delta)
	vel.z = move_toward(vel.z, 0, 10 * delta)
	if hurt_t <= 0:
		state = "free"

func _go_down():
	state = "down"
	anim.play("knockdown", 0.0, 1.0, anim.clip_len("knockdown"), 0.05, 0.01)

func _tick_down(delta):
	vel.x = move_toward(vel.x, 0, 8 * delta)
	vel.z = move_toward(vel.z, 0, 8 * delta)
	if anim.act_time > anim.clip_len("knockdown") - 0.1:
		anim.act_time = anim.clip_len("knockdown") - 0.12   # hold the floor pose

# ------------------------------------------------------------------ lock-on
func _toggle_lock():
	if lock_target:
		lock_target = null
	else:
		lock_target = arena.nearest_enemy(global_transform.origin, 14.0, facing)
	cam_rig.set_lock(lock_target)

# ------------------------------------------------------------------ footsteps
# v0.2 PSX: no foot IK — the walk/run cycle is stride-matched to ground
# speed (Anim rate = speed / natural speed), so the feet plant by the bake.
func _footsteps(delta):
	var sp = Vector2(vel.x, vel.z).length()
	if state != "free" or sp < 0.5:
		return
	var p = anim.phase
	var step = int(p * 2.0)
	if step != int(_step_phase * 2.0):
		arena.sfx("step", global_transform.origin, -14.0 + min(sp, 8.0))
	_step_phase = p
