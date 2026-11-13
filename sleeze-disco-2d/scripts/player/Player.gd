extends Node2D
# SLEEZE DISCO — Player (Godot 3.5 / GDScript, 2D).
#
# Port of web v7.6 (PORT_SPEC.md §1.4–§1.6, §2, §5, §6). Coordinates are
# the web canvas coordinates, 960x544, feet = node origin.
#
# Movement: velocity-based accel/decel (full speed in ~0.12 s, stop slide
# ~0.15 s). Attacks are SNAP-TO-BEAT: punch/kick/throw are judged at
# PRESS time and queued to fire on the next beat boundary. Parry, dodge
# and dance fire instantly, never queued. Combo breaks only when the
# player gets hit — off-beat swings still land (MISS retired for attacks).
#
const FXManagerScript := preload("res://scripts/fx/FXManager.gd")
const BeatData := preload("res://scripts/util/BeatData.gd")
const SheetFramesScript := preload("res://scripts/util/SheetFrames.gd")
# Vita mapping: Square punch, Triangle kick, Circle throw, Cross dodge,
# L1 parry, R1 finisher, Select dance, D-pad / left stick move.
# PC test keys: J/K/L/Space/S/E/F (see project.godot).

signal judgement_popup(judgement, offset_ms, text)
signal combo_changed(combo_count)
signal player_hurt
signal player_died
signal fever_changed(fever, tokens)
signal style_changed(rank, style_eff, moves_count)

enum State { IDLE, ATTACK, DODGE, HURT, DANCE, FINISHER }
enum AttackKind { PUNCH, KICK, THROW }

const WALK_SPEED_X := 280.0
const WALK_SPEED_Y := 180.0
const ACC := 280.0 / 0.12
const DEC := 280.0 / 0.15
const CLAMP_X_MIN := 60.0
const CLAMP_X_MAX := 900.0
const CLAMP_Y_MIN := 320.0
const CLAMP_Y_MAX := 480.0
const WALK_STRIDE := 28.0

const DODGE_TIME := 0.32
const DASH_SPEED := 700.0
const GHOST_INTERVAL := 0.08

const HITSTOP_NORMAL := 0.04
const HITSTOP_HEAVY := 0.08
const HITSTOP_FINISHER := 0.15

const BASE_DAMAGE := {AttackKind.PUNCH: 11, AttackKind.KICK: 16, AttackKind.THROW: 10}
const ATTACK_REACH := {AttackKind.PUNCH: 105.0, AttackKind.KICK: 135.0, AttackKind.THROW: 0.0}
const ATTACK_LUNGE := {AttackKind.PUNCH: 140.0, AttackKind.KICK: 180.0}
const ATK_TIME := 0.2
const GAP_CLOSE_MAX := 260.0
const THROW_SPEED := 680.0

const PARRY_WINDOW := 0.38
const DANCE_KICKS := ["spinback", "armada", "meialua", "sweep", "spinflip"]
const DANCE_CLIPS := ["hiphop", "headspin", "flair", "taunt"]
const FINISHER_CLIPS := ["headspin", "flair", "spinflip"]
const FINISHER_DAMAGE := 65
const FINISHER_RANGE := 320.0
const FINISHER_STUN := 1.5

const FEVER_PERFECT := 12
const FEVER_GOOD := 7
const FEVER_DANCE := 8
const FEVER_COUNTER := 10
const FEVER_PARRY_CLEAN := 15
const FEVER_PARRY_OFFBEAT := 3
const FEVER_KO := 6
const TOKEN_EVERY_COMBO := 12
const RUSH_BEATS := 8
const RUSH_SPD := 1.3

const STYLE_PERFECT := 3
const STYLE_GOOD := 1
const STYLE_COUNTER := 4
const STYLE_PARRY := 2
const STYLE_FINISHER := 2
const STYLE_STRING := 3
const RANK_THRESHOLDS := {"D": 0, "C": 20, "B": 40, "A": 70, "S": 110, "SLEEZE": 160}
const RANK_MULTS := {"D": 1.0, "C": 1.1, "B": 1.2, "A": 1.3, "S": 1.4, "SLEEZE": 1.5}
const MOVE_TYPES := ["punch", "kick", "throw", "dodge", "parry", "counter", "takedown", "dance"]

const DRAW_H := 200.0
const SHEET_KEY := "psxm"
const SHEET_FRAME_H := 225.0
const GROUND_BELOW_CENTRE := 104.0

var game = null  # Main — set at spawn. Owns score, FX, floats, banners.
var state: int = State.IDLE
var velocity := Vector2.ZERO
var facing := 1  # -1 left, +1 right
var hp := 100
var max_hp := 100

var combo_count := 0
var max_combo := 0
var perfects := 0
var kos := 0
var fit_tint := Color(1, 1, 1)  # shop jacket fit tint (Main sets per fight)
var style := 0.0
var style_moves := {}
var fever := 0
var tokens := 0
var rush_beats_left := 0
var rush_spd := 1.0

var _sprite: AnimatedSprite = null
var _ground_dx := 0.0  # SheetFrames.ground_dx(): feet-to-centre x, mirrored with flip_h
var _atk_timer := 0.0
var _atk_kind: int = AttackKind.PUNCH
var _dodge_timer := 0.0
var _dodge_cd := 0.0
var _dodge_dir := 1
var _ghost_timer := 0.0
var _dash_hit_done := false
var _hurt_timer := 0.0
var _parry_timer := 0.0
var _parry_cd := 0.0
var _parry_judgement: int = BeatData.Judgement.MISS
var _pending = null  # {kind, judgement, offset_ms}
var _pending_hit = null  # gap-closer: {kind, judgement, target, t, spin, string}
var _lunge_vx := 0.0
var _walk_dist := 0.0
var _punch_ix := 0
var _dance_kick_ix := 0
var _dance_clip_ix := 0
var _finisher_clip_ix := 0
var _atk_hist := []  # last 3 executed attack kinds (strings)
var _hitstop_active := false
var _hitstop_end_msec := 0  # real-time (OS.get_ticks_msec) hit-stop end
var _pose_lock := false  # win pose / dance break: _update_anim leaves the clip alone
var _glow_tex: Texture = null  # procedural neon glow for thrown drumsticks
var _current_clip := ""
var _clip_end_at := 0.0
var _idle_bob := 0.0

func _ready() -> void:
	add_to_group("player")
	# Baked-circle shadow under the feet (drawn before the sprite).
	add_child(FXManagerScript.make_shadow(110))
	# Neon glow for thrown drumsticks, generated in code (no texture file).
	_glow_tex = _make_glow_texture()
	_sprite = AnimatedSprite.new()
	_sprite.name = "Sprite"
	var clips := ["idle", "walk", "punch", "kick", "throw", "windup", "hit",
		"knock", "getup", "block", "upper", "taunt", "hiphop", "headspin",
		"flair", "spinback", "sweep", "armada", "meialua", "spinflip"]
	_sprite.frames = SheetFramesScript.build(SHEET_KEY, clips)
	_ground_dx = SheetFramesScript.ground_dx(SHEET_KEY)
	_sprite.offset.x = _ground_dx
	var s: float = DRAW_H / SHEET_FRAME_H
	_sprite.scale = Vector2(s, s)
	_sprite.position = Vector2(0, -GROUND_BELOW_CENTRE * s)
	add_child(_sprite)
	_play_clip("getup", 1.4)
	RhythmManager.connect("beat_hit", self, "_on_beat_hit")

func setup(p_game, spawn_pos: Vector2, p_max_hp: int) -> void:
	game = p_game
	position = spawn_pos
	max_hp = p_max_hp
	hp = max_hp

# Reset all per-fight state (web beginFight). Called by Main at fight start.
func reset_fight(spawn_pos: Vector2, p_max_hp: int) -> void:
	position = spawn_pos
	max_hp = p_max_hp
	hp = max_hp
	combo_count = 0
	max_combo = 0
	perfects = 0
	kos = 0
	_pose_lock = false
	_sprite.modulate = fit_tint
	style = 0.0
	style_moves = {}
	fever = 0
	tokens = 0
	rush_beats_left = 0
	rush_spd = 1.0
	state = State.IDLE
	velocity = Vector2.ZERO
	facing = 1
	_atk_timer = 0.0
	_dodge_timer = 0.0
	_dodge_cd = 0.0
	_hurt_timer = 0.0
	_parry_timer = 0.0
	_parry_cd = 0.0
	_pending = null
	_pending_hit = null
	_lunge_vx = 0.0
	_walk_dist = 0.0
	_punch_ix = 0
	_atk_hist = []
	for pr in _projectiles:
		if is_instance_valid(pr["node"]):
			pr["node"].queue_free()
	_projectiles.clear()
	_play_clip("getup", 1.4)
	emit_signal("fever_changed", fever, tokens)
	emit_signal("combo_changed", 0)
	emit_signal("style_changed", style_rank(), style_eff(), 0)

# --- per-frame ---------------------------------------------------------------

func _process(delta: float) -> void:
	# Hit-stop restore (real time — see _do_hitstop). Must run before the
	# delta<=0 early-out: during hit-stop delta IS 0, so only the wall
	# clock can end the freeze.
	if _hitstop_active:
		if OS.get_ticks_msec() >= _hitstop_end_msec:
			Engine.time_scale = 1.0
			_hitstop_active = false
		else:
			return
	if delta <= 0.0:
		return
	_update_timers(delta)
	_update_movement(delta)
	_update_attack_state(delta)
	_update_projectiles(delta)
	_update_anim(delta)

func _update_timers(delta: float) -> void:
	if _dodge_cd > 0.0:
		_dodge_cd -= delta
	if _parry_cd > 0.0:
		_parry_cd -= delta
	if _parry_timer > 0.0:
		_parry_timer -= delta
	if _hurt_timer > 0.0:
		_hurt_timer -= delta
		if _hurt_timer <= 0.0 and state == State.HURT:
			state = State.IDLE
	if _dodge_timer > 0.0:
		_dodge_timer -= delta
		if _dodge_timer <= 0.0 and state == State.DODGE:
			state = State.IDLE
	if _atk_timer > 0.0:
		_atk_timer -= delta
		if _atk_timer <= 0.0 and (state == State.ATTACK or state == State.DANCE or state == State.FINISHER):
			state = State.IDLE

func _update_movement(delta: float) -> void:
	var busy: bool = state == State.ATTACK or state == State.DODGE or state == State.HURT or state == State.DANCE or state == State.FINISHER
	var ix := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var iy := Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	var mx := 0.0
	var my := 0.0
	if not busy:
		mx = ix
		my = iy
	# Auto-face the nearest living enemy within 400 px, preferring the
	# held D-pad direction; flip only when |dx| > 12.
	_auto_face(ix)
	# Velocity-based accel / decel (web §1.4).
	velocity.x = _approach(velocity.x, mx * WALK_SPEED_X, (ACC if mx != 0.0 else DEC) * delta)
	velocity.y = _approach(velocity.y, my * WALK_SPEED_Y, (ACC if my != 0.0 else DEC) * delta)
	var step := velocity * delta
	# Dash: linear-decay burst, 700 px/s over the 0.32 s window.
	if state == State.DODGE:
		var dash_vx: float = DASH_SPEED * float(_dodge_dir) * (_dodge_timer / DODGE_TIME)
		step.x += dash_vx * delta
		_ghost_timer -= delta
		if _ghost_timer <= 0.0:
			_ghost_timer = GHOST_INTERVAL
			if game != null:
				game.fx.add_ghost(_sprite.frames.get_frame(_sprite.animation, _sprite.frame),
					position, _sprite.flip_h, Color(0.0, 0.94, 1.0), _sprite.scale.x,
					SheetFramesScript.ground_x(SHEET_KEY))
		_check_dash_strike()
	# Attack lunge burst, decays exp(-5 dt), zeroed below 2 px/s.
	if _lunge_vx != 0.0:
		step.x += _lunge_vx * delta
		_lunge_vx *= exp(-5.0 * delta)
		if abs(_lunge_vx) < 2.0:
			_lunge_vx = 0.0
	position += step
	position.x = clamp(position.x, CLAMP_X_MIN, CLAMP_X_MAX)
	position.y = clamp(position.y, CLAMP_Y_MIN, CLAMP_Y_MAX)
	# Walk cycle is driven by distance travelled (web §1.4).
	_walk_dist += abs(step.x) + abs(step.y) * 0.5

func _auto_face(held_x: float) -> void:
	var best = null
	var best_d := 400.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e.state == e.State.DEAD:
			continue
		var dx: float = e.position.x - position.x
		if held_x != 0.0 and sign(dx) != sign(held_x):
			continue
		if abs(dx) < best_d:
			best_d = abs(dx)
			best = e
	if best != null and abs(best.position.x - position.x) > 12.0:
		facing = 1 if best.position.x > position.x else -1

# --- input: queue, parry, dodge, dance, finisher -----------------------------

func _input(event: InputEvent) -> void:
	if game == null or game.screen != "fight":
		return
	if event.is_action_pressed("punch"):
		_queue_attack(AttackKind.PUNCH)
	elif event.is_action_pressed("kick"):
		_queue_attack(AttackKind.KICK)
	elif event.is_action_pressed("throw"):
		_queue_attack(AttackKind.THROW)
	elif event.is_action_pressed("dodge"):
		_try_dodge()
	elif event.is_action_pressed("parry"):
		_try_parry()
	elif event.is_action_pressed("finisher"):
		_try_finisher()
	elif event.is_action_pressed("dance"):
		_try_dance()

func _queue_attack(kind: int) -> void:
	if state == State.HURT:
		return
	# Judged at PRESS time; the swing fires on the next beat boundary.
	var result: Dictionary = RhythmManager.judge_attack()
	# One pending action at a time; a newer press replaces it.
	_pending = {"kind": kind, "judgement": result["judgement"], "offset_ms": result["offset_ms"]}
	if not RhythmManager.playing:
		_fire_queued()

func _on_beat_hit(_beat_index: int) -> void:
	if _pending != null and _atk_timer <= 0.0 and state != State.HURT and state != State.DODGE:
		_fire_queued()
	# Fever Rush rides the beat clock: 8 beats, then it is spent.
	if rush_beats_left > 0:
		rush_beats_left -= 1
		fever = int(100.0 * float(rush_beats_left) / float(RUSH_BEATS))
		if rush_beats_left <= 0:
			rush_spd = 1.0
			fever = 0
		emit_signal("fever_changed", fever, tokens)

func _fire_queued() -> void:
	if _pending == null:
		return
	var p: Dictionary = _pending
	_pending = null
	_execute_attack(int(p["kind"]), int(p["judgement"]), float(p["offset_ms"]))

func _execute_attack(kind: int, judgement: int, offset_ms: float) -> void:
	_atk_kind = kind
	_atk_timer = ATK_TIME / rush_spd
	state = State.ATTACK
	# Combo-string tracking (post-queue, last 3 executed attacks).
	var kind_name := "punch" if kind == AttackKind.PUNCH else ("kick" if kind == AttackKind.KICK else "throw")
	_atk_hist.append(kind_name)
	if _atk_hist.size() > 3:
		_atk_hist.pop_front()
	var string_ender := false
	if game != null and game.shop_combo and _atk_hist == ["punch", "punch", "kick"]:
		string_ender = true
	# Gap-closer: out of reach but within 260 px, facing the target.
	var reach: float = ATTACK_REACH[kind]
	if kind == AttackKind.KICK and game != null and game.unlock_spin_kick:
		reach = 175.0
	var target = _nearest_enemy_in_range(reach, 400.0)
	var dist := 9999.0
	if target != null:
		dist = abs(target.position.x - position.x)
	if kind != AttackKind.THROW and target != null and dist > reach and dist <= GAP_CLOSE_MAX and sign(target.position.x - position.x) == facing:
		var gap: float = dist - (reach - 12.0)
		_lunge_vx = facing * min(1500.0, gap * 9.5) * rush_spd
		_pending_hit = {"kind": kind, "judgement": judgement, "offset_ms": offset_ms,
			"target": target, "t": 0.15 / rush_spd, "spin": false, "string": string_ender}
		_play_attack_clip(kind, judgement, string_ender, true)
		return
	if kind == AttackKind.THROW:
		_spawn_throw(judgement, offset_ms)
		_play_clip("throw", _clip_dur("throw", 0.7))
	else:
		_apply_melee(kind, judgement, offset_ms, reach, string_ender, false)
		_play_attack_clip(kind, judgement, string_ender, false)
	# Attack judgement tone on the swing (web §2): PERFECT 780 Hz, else 420.
	RhythmManager.play_blip("perfect" if judgement == BeatData.Judgement.PERFECT else "good")

func _play_attack_clip(kind: int, judgement: int, string_ender: bool, _gap: bool) -> void:
	if string_ender:
		_play_clip("spinback", _clip_dur("spinback", 1.2))
		return
	match kind:
		AttackKind.PUNCH:
			_punch_ix += 1
			if _punch_ix % 3 == 0:
				_play_clip("upper", _clip_dur("upper", 0.6))
			else:
				_play_clip("punch", _clip_dur("punch", 0.6))
		AttackKind.KICK:
			if judgement == BeatData.Judgement.PERFECT:
				var clip: String = DANCE_KICKS[_dance_kick_ix % DANCE_KICKS.size()]
				_dance_kick_ix += 1
				_play_clip(clip, _clip_dur(clip, 1.2))
			elif game != null and game.unlock_spin_kick:
				_play_clip("spinback", _clip_dur("spinback", 1.2))
			else:
				_play_clip("kick", _clip_dur("kick", 0.8))

func _apply_melee(kind: int, judgement: int, offset_ms: float, reach: float, string_ender: bool, from_gap: bool) -> void:
	# Lunge burst on the swing.
	if kind == AttackKind.PUNCH:
		_lunge_vx = ATTACK_LUNGE[kind] * facing
	elif kind == AttackKind.KICK:
		_lunge_vx = ATTACK_LUNGE[kind] * facing
	var base: int = BASE_DAMAGE[kind]
	if kind == AttackKind.KICK and game != null and game.unlock_spin_kick:
		base = 22
	var mult := 1.0
	match judgement:
		BeatData.Judgement.PERFECT:
			mult = 1.5
		BeatData.Judgement.GOOD:
			mult = 1.1
	if string_ender:
		mult *= 1.5
	var damage := int(round(base * mult))
	var hit_any := false
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e.state == e.State.DEAD:
			continue
		var dx: float = e.position.x - position.x
		var dy: float = e.position.y - position.y
		if abs(dx) > reach or abs(dy) > 55.0:
			continue
		if sign(dx) != facing and abs(dx) > 12.0:
			continue
		_land_hit(e, damage, judgement, offset_ms, kind == AttackKind.KICK, string_ender)
		hit_any = true
	if hit_any:
		_do_hitstop(judgement == BeatData.Judgement.PERFECT or kind == AttackKind.KICK)

func _land_hit(enemy, damage: int, judgement: int, offset_ms: float, heavy: bool, string_ender: bool) -> void:
	var died: bool = enemy.take_hit(damage, judgement, position)
	combo_count += 1
	max_combo = max(max_combo, combo_count)
	if judgement == BeatData.Judgement.PERFECT:
		perfects += 1
		style += STYLE_PERFECT
		_add_fever(FEVER_PERFECT)
	elif judgement == BeatData.Judgement.GOOD:
		style += STYLE_GOOD
		_add_fever(FEVER_GOOD)
	# Style variety: the move type joins the set.
	var move_name := "punch"
	if _atk_kind == AttackKind.KICK:
		move_name = "kick"
	elif _atk_kind == AttackKind.THROW:
		move_name = "throw"
	style_moves[move_name] = true
	if string_ender:
		style += STYLE_STRING
		if game != null:
			game.add_float("STRING!", position + Vector2(0, -160), Color(1.0, 0.78, 0.24))
	if game != null:
		game.gain_score(damage * (1 + combo_count / 5))
		game.add_float(RhythmManager.judgement_name(judgement) + " -" + str(damage),
			enemy.position + Vector2(0, -140),
			Color(1.0, 0.78, 0.24) if judgement == BeatData.Judgement.PERFECT else (Color(0.0, 0.94, 1.0) if judgement == BeatData.Judgement.GOOD else Color(1, 1, 1)))
		game.fx.hit_sparks(enemy.position + Vector2(0, -90), judgement)
		game.fx.impact_ring(enemy.position + Vector2(0, -40), heavy, RhythmManager.beat_dur_sec())
		game.add_shake(10 if heavy else (7 if judgement == BeatData.Judgement.PERFECT else 0))
	emit_signal("judgement_popup", judgement, offset_ms,
		RhythmManager.judgement_name(judgement) + "  x" + str(combo_count))
	# Token every 12 combo.
	if combo_count % TOKEN_EVERY_COMBO == 0:
		var cap: int = game.token_cap() if game != null else 3
		if tokens < cap:
			tokens += 1
			if game != null:
				game.add_float("★ TOKEN +1", position + Vector2(0, -160), Color(1.0, 0.78, 0.24))
			emit_signal("fever_changed", fever, tokens)
	if died:
		kos += 1
		if game != null:
			game.gain_score(100)
			game.add_float("KO +100", enemy.position + Vector2(0, -170), Color(1.0, 0.78, 0.24))
			game.add_shake(12)
		_add_fever(FEVER_KO)
		_do_hitstop(true)
	emit_signal("combo_changed", combo_count)
	emit_signal("style_changed", style_rank(), style_eff(), style_moves.size())

func _try_dodge() -> void:
	if state == State.HURT or state == State.DODGE or _dodge_cd > 0.0:
		return
	if _atk_timer > 0.0:
		return
	state = State.DODGE
	_dodge_timer = DODGE_TIME
	_dodge_cd = 1.5 * RhythmManager.beat_dur_sec()
	_dodge_dir = facing
	_ghost_timer = 0.0
	_dash_hit_done = false
	style_moves["dodge"] = true
	if game != null:
		game.add_shake(4)
		game.fx.burst(position + Vector2(0, -10), Color(0.0, 0.94, 1.0), 10)
		game.add_float("PHASE DASH", position + Vector2(0, -160), Color(0.0, 0.94, 1.0))

func _check_dash_strike() -> void:
	if game == null or not game.unlock_dash_strike or _dash_hit_done:
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e.state == e.State.DEAD:
			continue
		if abs(e.position.x - position.x) < 80.0 and abs(e.position.y - position.y) < 60.0:
			_dash_hit_done = true
			var died: bool = e.take_hit(14, BeatData.Judgement.HIT, position)
			combo_count += 1
			max_combo = max(max_combo, combo_count)
			game.add_float("DASH STRIKE -14", e.position + Vector2(0, -140), Color(0.0, 0.94, 1.0))
			game.fx.hit_sparks(e.position + Vector2(0, -90), BeatData.Judgement.HIT)
			if died:
				game.gain_score(100)
			break

func _try_parry() -> void:
	if state == State.HURT or state == State.DODGE or _parry_cd > 0.0 or _parry_timer > 0.0:
		return
	var result: Dictionary = RhythmManager.judge_parry()
	_parry_judgement = int(result["judgement"])
	_parry_timer = PARRY_WINDOW
	_parry_cd = 2.0 * RhythmManager.beat_dur_sec()
	_play_clip("block", PARRY_WINDOW)
	style_moves["parry"] = true
	# COUNTER: press while a telegraphing enemy is within 260 px.
	var counter_target = null
	var best_d := 260.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e.state == e.State.DEAD:
			continue
		if not e.is_telegraphing():
			continue
		var d := abs(e.position.x - position.x)
		if d < best_d:
			best_d = d
			counter_target = e
	if counter_target != null:
		_do_counter(counter_target)
	else:
		if game != null:
			game.add_float("PARRY STANCE", position + Vector2(0, -160), Color(0.0, 0.94, 1.0))

func _do_counter(enemy) -> void:
	enemy.apply_stun(1.6)
	enemy.set_recover(0.4)
	enemy.take_hit(20, BeatData.Judgement.PERFECT, position, {"knock": 24 * facing, "heavy": true})
	style += STYLE_COUNTER
	style_moves["counter"] = true
	_add_fever(FEVER_COUNTER)
	combo_count += 1
	max_combo = max(max_combo, combo_count)
	if game != null:
		game.gain_score(20 * (1 + combo_count / 5))
		game.add_float("COUNTER! -20", enemy.position + Vector2(0, -150), Color(1.0, 0.78, 0.24))
		game.add_shake(10)
	_do_hitstop(true)
	RhythmManager.play_blip("counter")
	emit_signal("style_changed", style_rank(), style_eff(), style_moves.size())

# Called by Enemy.resolve_strike when a strike lands while parryT > 0.
# Returns true when the parry consumed the strike.
func check_parry_strike(enemy) -> bool:
	if _parry_timer <= 0.0:
		return false
	enemy.apply_stun(1.6)
	var clean: bool = _parry_judgement == BeatData.Judgement.PERFECT or _parry_judgement == BeatData.Judgement.GOOD
	if clean:
		style += STYLE_PARRY
		if game != null:
			game.gain_score(200)
			game.add_float("PARRIED! +200", position + Vector2(0, -160), Color(0.0, 0.94, 1.0))
		_add_fever(FEVER_PARRY_CLEAN)
	else:
		if game != null:
			game.add_float("PARRIED (OFF-BEAT) +3", position + Vector2(0, -160), Color(0.55, 0.58, 0.65))
		_add_fever(FEVER_PARRY_OFFBEAT)
	_parry_timer = 0.0
	emit_signal("style_changed", style_rank(), style_eff(), style_moves.size())
	return true

# Called by Main's ring update when a ring touches the player while parryT > 0.
func check_parry_ring(ring_owner) -> bool:
	if _parry_timer <= 0.0:
		return false
	if ring_owner != null and ring_owner.has_method("apply_stun"):
		ring_owner.apply_stun(1.6)
		if ring_owner.has_method("set_chase"):
			ring_owner.set_chase()
	var clean: bool = _parry_judgement == BeatData.Judgement.PERFECT or _parry_judgement == BeatData.Judgement.GOOD
	if clean:
		style += STYLE_PARRY
		if game != null:
			game.gain_score(200)
			game.add_float("BLAST PARRIED! +200", position + Vector2(0, -160), Color(0.0, 0.94, 1.0))
		_add_fever(FEVER_PARRY_CLEAN)
	else:
		if game != null:
			game.add_float("BLAST PARRIED (OFF-BEAT) +3", position + Vector2(0, -160), Color(0.55, 0.58, 0.65))
		_add_fever(FEVER_PARRY_OFFBEAT)
	_parry_timer = 0.0
	emit_signal("style_changed", style_rank(), style_eff(), style_moves.size())
	return true

func _try_dance() -> void:
	if state == State.HURT or state == State.DODGE or _atk_timer > 0.0:
		return
	state = State.DANCE
	_atk_timer = RhythmManager.beat_dur_sec()
	var clip: String = DANCE_CLIPS[_dance_clip_ix % DANCE_CLIPS.size()]
	_dance_clip_ix += 1
	_play_clip(clip, RhythmManager.beat_dur_sec())
	_add_fever(FEVER_DANCE)
	style_moves["dance"] = true
	RhythmManager.play_blip("dance")
	if game != null:
		game.add_float("DANCE +8 FEVER", position + Vector2(0, -160), Color(1.0, 0.2, 0.8))
	emit_signal("style_changed", style_rank(), style_eff(), style_moves.size())

func _try_finisher() -> void:
	if state == State.HURT or state == State.DODGE or _atk_timer > 0.0:
		return
	if tokens <= 0:
		if game != null:
			game.add_float("NO TOKENS", position + Vector2(0, -160), Color(0.55, 0.58, 0.65))
		RhythmManager.play_blip("notokens")
		return
	tokens -= 1
	state = State.FINISHER
	_atk_timer = RhythmManager.beat_dur_sec() * 3.0
	var clip: String = FINISHER_CLIPS[_finisher_clip_ix % FINISHER_CLIPS.size()]
	_finisher_clip_ix += 1
	_play_clip(clip, RhythmManager.beat_dur_sec() * 3.0)
	style += STYLE_FINISHER
	style_moves["takedown"] = true
	var hit_any := false
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e.state == e.State.DEAD:
			continue
		if abs(e.position.x - position.x) > FINISHER_RANGE:
			continue
		var died: bool = e.take_hit(FINISHER_DAMAGE, BeatData.Judgement.PERFECT, position, {"stun": FINISHER_STUN, "flash": 0.2})
		combo_count += 1
		max_combo = max(max_combo, combo_count)
		if game != null:
			game.add_float("SMASH -65!", e.position + Vector2(0, -150), Color(1.0, 0.78, 0.24))
			game.fx.burst(e.position + Vector2(0, -90), Color(1.0, 0.78, 0.24), 22)
		if died and game != null:
			game.gain_score(100)
		hit_any = true
	if hit_any:
		_do_hitstop_finisher()
	if game != null:
		game.banner("★ BEAT DROP FINISHER ★", 1.5)
		game.add_shake(15)
	emit_signal("fever_changed", fever, tokens)
	emit_signal("style_changed", style_rank(), style_eff(), style_moves.size())

# --- throw projectiles ---------------------------------------------------------

var _projectiles := []  # {node, vx, judgement, offset_ms}

# 32x32 radial-gradient cyan glow (ImageTexture, no asset file).
func _make_glow_texture() -> Texture:
	var img := Image.new()
	img.create(32, 32, false, Image.FORMAT_RGBA8)
	img.lock()
	for y in range(32):
		for x in range(32):
			var d := Vector2(x - 15.5, y - 15.5).length() / 16.0
			var a := clamp(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.0, 0.94, 1.0, a * a))
	img.unlock()
	var tex := ImageTexture.new()
	tex.create_from_image(img)
	return tex

func _spawn_throw(judgement: int, offset_ms: float) -> void:
	var p := Node2D.new()
	var spr := Sprite.new()
	spr.texture = _glow_tex
	spr.scale = Vector2(0.6, 0.6)
	p.add_child(spr)
	p.position = position + Vector2(30 * facing, -65)
	add_child(p)
	_projectiles.append({"node": p, "vx": THROW_SPEED * facing, "judgement": judgement, "offset_ms": offset_ms})

func _update_projectiles(delta: float) -> void:
	for i in range(_projectiles.size() - 1, -1, -1):
		var pr: Dictionary = _projectiles[i]
		var node: Node2D = pr["node"]
		if not is_instance_valid(node):
			_projectiles.remove(i)
			continue
		node.position.x += float(pr["vx"]) * delta
		var hit := false
		for e in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(e) or e.state == e.State.DEAD:
				continue
			if abs(e.position.x - node.position.x) < 35.0 and abs((e.position.y - 60.0) - node.position.y) < 60.0:
				_land_hit(e, BASE_DAMAGE[AttackKind.THROW], int(pr["judgement"]), float(pr["offset_ms"]), false, false)
				hit = true
				break
		if hit or node.position.x < 0.0 or node.position.x > 960.0:
			node.queue_free()
			_projectiles.remove(i)

# --- getting hit ---------------------------------------------------------------

func take_hit(damage: int) -> void:
	if state == State.DODGE or _dodge_timer > 0.0:
		return
	hp = max(hp - damage, 0)
	combo_count = 0
	style *= 0.75
	_hurt_timer = 0.25
	state = State.HURT
	_play_clip("hit", 0.35)
	if game != null:
		game.add_shake(9)
		game.add_float("-" + str(damage), position + Vector2(0, -150), Color(0.9, 0.2, 0.2))
		game.add_float("STYLE -25%", position + Vector2(0, -180), Color(0.55, 0.58, 0.65))
	emit_signal("player_hurt")
	emit_signal("combo_changed", 0)
	emit_signal("style_changed", style_rank(), style_eff(), style_moves.size())
	if hp <= 0:
		emit_signal("player_died")

# --- fever / style / score helpers ---------------------------------------------

func _add_fever(n: int) -> void:
	if rush_beats_left > 0:
		return  # no gains land during a Rush
	if game != null and game.shop_faster_fever:
		n = int(round(n * 1.5))
	fever = int(min(100, fever + n))
	if fever >= 100 and rush_beats_left <= 0:
		_start_rush()
	emit_signal("fever_changed", fever, tokens)

func _start_rush() -> void:
	rush_beats_left = RUSH_BEATS
	rush_spd = RUSH_SPD
	fever = 100
	if game != null:
		game.banner("FEVER RUSH!", 2.0)
	RhythmManager.play_blip("rush")
	emit_signal("fever_changed", fever, tokens)

func style_eff() -> float:
	return style * (1.0 + 0.1 * float(style_moves.size()))

func style_rank() -> String:
	var eff := style_eff()
	if eff >= RANK_THRESHOLDS["SLEEZE"]:
		return "SLEEZE"
	if eff >= RANK_THRESHOLDS["S"]:
		return "S"
	if eff >= RANK_THRESHOLDS["A"]:
		return "A"
	if eff >= RANK_THRESHOLDS["B"]:
		return "B"
	if eff >= RANK_THRESHOLDS["C"]:
		return "C"
	return "D"

func rank_mult() -> float:
	return float(RANK_MULTS[style_rank()])

# --- animation -------------------------------------------------------------------

# Win pose / dance break: hold a looping clip until clear_pose().
# Used by Main for the end-screen pose and the endless dance break.
func play_pose(clip: String) -> void:
	if _sprite == null or _sprite.frames == null or not _sprite.frames.has_animation(clip):
		return
	_pose_lock = true
	_current_clip = clip
	_sprite.animation = clip
	_sprite.speed_scale = 1.0
	_sprite.frame = 0
	_sprite.playing = true
	state = State.IDLE
	_atk_timer = 0.0
	velocity = Vector2.ZERO

func clear_pose() -> void:
	_pose_lock = false
	_current_clip = ""

func _play_clip(clip: String, dur: float) -> void:
	if _sprite.frames == null or not _sprite.frames.has_animation(clip):
		return
	_current_clip = clip
	_sprite.animation = clip
	var natural := SheetFramesScript.natural_dur(SHEET_KEY, clip)
	_sprite.speed_scale = natural / max(dur, 0.05) if natural > 0.0 else 1.0
	_sprite.frame = 0
	_sprite.playing = true
	_clip_end_at = OS.get_ticks_msec() / 1000.0 + dur

func _clip_dur(clip: String, beats: float) -> float:
	var natural := SheetFramesScript.natural_dur(SHEET_KEY, clip)
	return max(0.25, min(natural, beats * RhythmManager.beat_dur_sec()))

func _update_anim(delta: float) -> void:
	if _pose_lock:
		return  # win pose / dance break holds its clip
	_sprite.flip_h = facing == -1
	_sprite.offset.x = _ground_dx * (-1.0 if _sprite.flip_h else 1.0)
	var bob := sin(RhythmManager.beat_phase01() * TAU) * 2.0
	match state:
		State.ATTACK, State.FINISHER:
			# Lunge pose: tilt + stretch on the swing.
			var t := 1.0 - clamp(_atk_timer / max(ATK_TIME / rush_spd, 0.01), 0.0, 1.0)
			_sprite.rotation = -0.18 * float(facing) * sin(t * PI)
			_sprite.scale = Vector2((DRAW_H / SHEET_FRAME_H) * (1.0 + 0.08 * sin(t * PI)), DRAW_H / SHEET_FRAME_H)
			_sprite.position = Vector2(0, -GROUND_BELOW_CENTRE * (DRAW_H / SHEET_FRAME_H) + bob * 0.3)
		State.DODGE:
			_sprite.rotation = 0.9 * float(facing)
			_sprite.scale = Vector2((DRAW_H / SHEET_FRAME_H) * 1.15, (DRAW_H / SHEET_FRAME_H) * 0.8)
			_sprite.position = Vector2(0, -GROUND_BELOW_CENTRE * (DRAW_H / SHEET_FRAME_H))
		State.HURT:
			_sprite.rotation = 0.25 * float(-facing)
			_sprite.scale = Vector2(DRAW_H / SHEET_FRAME_H, DRAW_H / SHEET_FRAME_H)
			_sprite.position = Vector2(0, -GROUND_BELOW_CENTRE * (DRAW_H / SHEET_FRAME_H))
		_:
			_sprite.rotation = 0.0
			_sprite.scale = Vector2(DRAW_H / SHEET_FRAME_H, DRAW_H / SHEET_FRAME_H)
			_sprite.position = Vector2(0, -GROUND_BELOW_CENTRE * (DRAW_H / SHEET_FRAME_H) + bob)
			# Walk cycle by distance; idle breathes on the beat.
			var moving := velocity.length() > 20.0
			if moving and state == State.IDLE:
				if _current_clip != "walk":
					_current_clip = "walk"
					_sprite.animation = "walk"
					_sprite.playing = false
				var phase: float = fmod(_walk_dist / WALK_STRIDE, 1.0)
				_sprite.frame = int(phase * 14.0) % 14
			elif state == State.IDLE:
				if _current_clip != "idle":
					_current_clip = "idle"
					_sprite.animation = "idle"
					# Idle ping-pongs once per 2 beats.
					_sprite.speed_scale = (9.0 / (2.0 * RhythmManager.beat_dur_sec())) / 24.0
					_sprite.playing = true

# --- helpers ---------------------------------------------------------------------

func _nearest_enemy_in_range(_reach: float, max_dist: float):
	var best = null
	var best_d := max_dist
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e.state == e.State.DEAD:
			continue
		var d := abs(e.position.x - position.x)
		if d < best_d:
			best_d = d
			best = e
	return best

func _update_attack_state(delta: float) -> void:
	# Gap-closer pending hit: resolve when in reach or the window ends.
	if _pending_hit != null:
		var ph: Dictionary = _pending_hit
		ph["t"] = float(ph["t"]) - delta
		var target = ph["target"]
		if not is_instance_valid(target) or target.state == target.State.DEAD:
			_pending_hit = null
			_lunge_vx = 0.0
			return
		var reach: float = ATTACK_REACH[int(ph["kind"])]
		if int(ph["kind"]) == AttackKind.KICK and game != null and game.unlock_spin_kick:
			reach = 175.0
		var dx: float = target.position.x - position.x
		var dy: float = target.position.y - position.y
		if abs(dx) < reach and abs(dy) < 55.0:
			_pending_hit = null
			_lunge_vx = 0.0
			_apply_melee(int(ph["kind"]), int(ph["judgement"]), float(ph["offset_ms"]), reach, bool(ph["string"]), true)
		elif float(ph["t"]) <= 0.0:
			_pending_hit = null
			_lunge_vx = 0.0
			# The swing still lands at full reach if anything is there.
			_apply_melee(int(ph["kind"]), int(ph["judgement"]), float(ph["offset_ms"]), reach, bool(ph["string"]), true)

func _approach(v: float, target: float, step: float) -> float:
	if v < target:
		return min(v + step, target)
	if v > target:
		return max(v - step, target)
	return v

# Hit-stop: freeze the sim for 40/80/150 ms. Godot 3.5's SceneTreeTimer
# cannot run while time_scale is 0 (create_timer has no ignore_time_scale
# argument in 3.x — that's Godot 4), so a yield-based restore would freeze
# forever. Instead the freeze is ended by the wall clock in _process.
func _do_hitstop(heavy: bool) -> void:
	var dur: float = HITSTOP_HEAVY if heavy else HITSTOP_NORMAL
	var end_msec: int = OS.get_ticks_msec() + int(dur * 1000.0)
	if _hitstop_active:
		# Web rule: hit-stop extends to the longer freeze.
		_hitstop_end_msec = max(_hitstop_end_msec, end_msec)
		return
	_hitstop_active = true
	_hitstop_end_msec = end_msec
	Engine.time_scale = 0.0

func _do_hitstop_finisher() -> void:
	var end_msec: int = OS.get_ticks_msec() + int(HITSTOP_FINISHER * 1000.0)
	if _hitstop_active:
		_hitstop_end_msec = max(_hitstop_end_msec, end_msec)
		return
	_hitstop_active = true
	_hitstop_end_msec = end_msec
	Engine.time_scale = 0.0
