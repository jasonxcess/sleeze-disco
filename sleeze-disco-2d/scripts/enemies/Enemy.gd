extends Node2D
# SLEEZE DISCO — Enemy (Godot 3.5 / GDScript, 2D).
#
# Port of web v7.6 (PORT_SPEC.md §3). Six types: stan / charger /
# bruiser + lab bosses DR. CLIPBOARD (boss1), SUBJECT SEVEN (boss2),
# VEX. "Idol" is gone — never use that name.
#
# AI: chase -> windup -> telegraph -> strike -> recover -> chase.
# Telegraphs snap to the next beat (never sooner than ~0.25 s); strikes
# resolve at the telegraph->strike transition. One attacker at a time:
# a windup holds while another enemy within 120 px is telegraphing,
# striking or sweeping. Bosses add signatures: Rope Sweep (boss1),
# Triple Tap (boss2), Spotlight Blast (VEX, 66%/33% phases).
#
const FXManagerScript := preload("res://scripts/fx/FXManager.gd")
const BeatData := preload("res://scripts/util/BeatData.gd")
const SheetFramesScript := preload("res://scripts/util/SheetFrames.gd")

signal enemy_died(enemy)
signal boss_phase_changed(phase)

enum Kind { STAN, CHARGER, BRUISER, BOSS1, BOSS2, VEX }
enum State { CHASE, WINDUP, TELEGRAPH, STRIKE, RECOVER, BLAST, SWEEP, STUNNED, TAUNT, DEAD }

# Spawn stats (verbatim, PORT_SPEC.md §3.1).
const STATS := {
	Kind.STAN:    {"name": "BOUNCER",        "hp": 35,  "spd": 65.0, "dmg": 8,
	               "sheet": "thug", "draw_h": 185.0, "frame_h": 209.0,
	               "color": Color(0.0, 0.94, 1.0), "tint": Color(1, 1, 1)},
	Kind.CHARGER: {"name": "RUSHER",         "hp": 45,  "spd": 95.0, "dmg": 14,
	               "sheet": "dead", "draw_h": 190.0, "frame_h": 232.0,
	               "color": Color(0.9, 0.2, 0.2), "tint": Color(1, 1, 1)},
	Kind.BRUISER: {"name": "HEAVY",          "hp": 95,  "spd": 42.0, "dmg": 18,
	               "sheet": "thug", "draw_h": 225.0, "frame_h": 209.0,
	               "color": Color(0.62, 0.31, 0.87), "tint": Color(0.85, 0.7, 1.0)},
	Kind.BOSS1:   {"name": "DR. CLIPBOARD",  "hp": 140, "spd": 55.0, "dmg": 14,
	               "sheet": "thug", "draw_h": 210.0, "frame_h": 209.0,
	               "color": Color(1.0, 0.78, 0.24), "tint": Color(1.0, 0.82, 0.45)},
	Kind.BOSS2:   {"name": "SUBJECT SEVEN",  "hp": 180, "spd": 70.0, "dmg": 16,
	               "sheet": "dead", "draw_h": 215.0, "frame_h": 232.0,
	               "color": Color(1.0, 0.2, 0.8), "tint": Color(1.0, 0.65, 0.9)},
	Kind.VEX:     {"name": "VEX",            "hp": 280, "spd": 60.0, "dmg": 16,
	               "sheet": "psxw", "draw_h": 250.0, "frame_h": 214.0,
	               "color": Color(1.0, 0.2, 0.8), "tint": Color(1, 1, 1)},
}
const CLAMP_X_MIN := 40.0
const CLAMP_X_MAX := 920.0
const CLAMP_Y_MIN := 320.0
const CLAMP_Y_MAX := 480.0
const CHASE_RANGE := 72.0
const STRIKE_RANGE := 90.0
const HOLD_RADIUS := 120.0
const FACING_DEADZONE := 24.0
const GROUND_BELOW_CENTRE := 104.0

var game = null
var kind: int = Kind.STAN
var hp := 35
var max_hp := 35
var state: int = State.CHASE
var boss_phase := 0
var facing := -1

var _sprite: AnimatedSprite = null
var _ground_dx := 0.0  # SheetFrames.ground_dx(): feet-to-centre x, mirrored with flip_h
var _shadow: Polygon2D = null
var _counter_label: Label = null
var _excl_label: Label = null
var _vel := Vector2.ZERO
var _kvx := 0.0
var _state_t := 0.0
var _windup_max := 0.85
var _tele_dur := 0.3
var _flash_t := 0.0
var _stun_t := 0.0
var _taunt_t := 0.0
var _walk_dist := 0.0
var _speed_mul := 1.0
# Boss signature state (web §3.3).
var _sig_t := 7.0
var _sig_announced := false
var _blast_t := 8.0
var _blast_announced := false
var _chain := 0
var _chain_armed := false
var _corpse_t := 0.0
var _current_clip := ""

func setup(p_game, p_kind: int, spawn_pos: Vector2, p_speed_mul: float = 1.0) -> void:
	game = p_game
	kind = p_kind
	var st: Dictionary = STATS[kind]
	max_hp = int(st["hp"])
	hp = max_hp
	_speed_mul = p_speed_mul
	position = spawn_pos
	state = State.CHASE
	_state_t = 0.0
	_windup_max = 0.7 + randf() * 0.3
	_sprite = AnimatedSprite.new()
	_sprite.name = "Sprite"
	var clips := ["idle", "walk", "punch", "kick", "throw", "windup", "hit",
		"knock", "getup", "block", "upper", "taunt", "hiphop", "headspin",
		"flair", "spinback", "sweep", "armada", "meialua", "spinflip"]
	_sprite.frames = SheetFramesScript.build(String(st["sheet"]), clips)
	_ground_dx = SheetFramesScript.ground_dx(String(st["sheet"]))
	_sprite.offset.x = _ground_dx
	var s: float = float(st["draw_h"]) / float(st["frame_h"])
	_sprite.scale = Vector2(s, s)
	_sprite.position = Vector2(0, -GROUND_BELOW_CENTRE * s)
	_sprite.modulate = st["tint"]
	_shadow = FXManagerScript.make_shadow(100)
	add_child(_shadow)
	add_child(_sprite)
	# Gold COUNTER prompt + red "!" shown over a telegraphing enemy.
	_counter_label = Label.new()
	_counter_label.text = "COUNTER"
	_counter_label.add_color_override("font_color", Color(1.0, 0.78, 0.24))
	_counter_label.visible = false
	_counter_label.rect_position = Vector2(-34, -float(st["draw_h"]) - 44)
	add_child(_counter_label)
	_excl_label = Label.new()
	_excl_label.text = "!"
	_excl_label.add_color_override("font_color", Color(0.9, 0.2, 0.2))
	_excl_label.visible = false
	_excl_label.rect_position = Vector2(-4, -float(st["draw_h"]) - 24)
	add_child(_excl_label)
	add_to_group("enemies")
	_play_clip("walk", 1.0)

func is_telegraphing() -> bool:
	return state == State.TELEGRAPH

func apply_stun(t: float) -> void:
	if state == State.DEAD:
		return
	_stun_t = t
	state = State.STUNNED

func set_recover(t: float) -> void:
	if state == State.DEAD:
		return
	state = State.RECOVER
	_state_t = t

func set_chase() -> void:
	if state == State.DEAD:
		return
	state = State.CHASE
	_state_t = 0.0

func _process(delta: float) -> void:
	if state == State.DEAD:
		_corpse_t += delta
		if _corpse_t > 1.6:
			var a: float = clamp(1.0 - (_corpse_t - 1.6) / 0.6, 0.0, 1.0)
			_sprite.modulate.a = a
			if _shadow != null:
				_shadow.color.a = 0.45 * a
		if _corpse_t >= 2.2:
			queue_free()
		return
	if delta <= 0.0:
		return
	if _flash_t > 0.0:
		_flash_t -= delta
	# Knockback arc applies in every state, even stun/taunt.
	if _kvx != 0.0:
		position.x += _kvx * delta
		_kvx *= exp(-delta / 0.08)
		if abs(_kvx) < 5.0:
			_kvx = 0.0
	if _stun_t > 0.0:
		_stun_t -= delta
		if _stun_t <= 0.0:
			state = State.CHASE
			_state_t = 0.0
		_update_anim(delta)
		return
	if _taunt_t > 0.0:
		_taunt_t -= delta
		# Taunt freezes the AI, but a recover timer still ticks.
		if state == State.RECOVER:
			_state_t -= delta
			if _state_t <= 0.0:
				state = State.CHASE
				_state_t = 0.0
		_update_anim(delta)
		return
	var player = game.player if game != null else null
	if player == null or not is_instance_valid(player):
		return
	var to_player: Vector2 = player.position - position
	var dist := to_player.length()
	var dir := to_player.normalized() if dist > 0.01 else Vector2.ZERO
	# Facing flips only when |dx| > 24 (web deadzone).
	if abs(to_player.x) > FACING_DEADZONE:
		facing = 1 if to_player.x > 0.0 else -1
	# Boss signature timers.
	_update_boss_timers(delta)
	var spd: float = float(STATS[kind]["spd"]) * _speed_mul
	match state:
		State.CHASE:
			var desired := Vector2.ZERO
			if dist > CHASE_RANGE:
				desired = Vector2(dir.x * spd, dir.y * spd * 0.6)
			_vel = _vel.linear_interpolate(desired, min(1.0, 8.0 * delta))
			position += _vel * delta
			_walk_dist += _vel.length() * delta
			if dist <= CHASE_RANGE:
				_vel = Vector2.ZERO
				state = State.WINDUP
				_state_t = _windup_max
		State.WINDUP:
			_vel = _vel.linear_interpolate(Vector2.ZERO, min(1.0, 8.0 * delta))
			position += _vel * delta
			# One attacker at a time: hold while a neighbour telegraphs,
			# strikes or sweeps within 120 px.
			if not _neighbour_swinging():
				_state_t -= delta
				if _state_t <= 0.0:
					_begin_telegraph()
		State.TELEGRAPH:
			# Step-in at 0.6x speed so a short gap closes, but a player
			# who walked away still outruns the strike.
			var desired2 := Vector2(dir.x * spd * 0.6, dir.y * spd * 0.36)
			_vel = _vel.linear_interpolate(desired2, min(1.0, 8.0 * delta))
			position += _vel * delta
			_walk_dist += _vel.length() * delta
			_state_t -= delta
			if _state_t <= 0.0:
				_resolve_strike()
				# A parry stuns the enemy inside _resolve_strike; only
				# enter STRIKE when the enemy is still telegraphing.
				if state == State.TELEGRAPH:
					state = State.STRIKE
					_state_t = 0.12
		State.STRIKE:
			_vel = _vel.linear_interpolate(Vector2.ZERO, min(1.0, 8.0 * delta))
			position += _vel * delta
			_state_t -= delta
			if _state_t <= 0.0:
				if kind == Kind.BOSS2 and _chain > 0:
					_chain -= 1
					state = State.WINDUP
					_state_t = 0.35
				else:
					_chain_armed = false
					state = State.RECOVER
					_state_t = 0.4
		State.RECOVER:
			_vel = _vel.linear_interpolate(Vector2.ZERO, min(1.0, 8.0 * delta))
			position += _vel * delta
			_state_t -= delta
			if _state_t <= 0.0:
				state = State.CHASE
				_state_t = 0.0
		State.BLAST, State.SWEEP:
			_state_t -= delta
			if _state_t <= 0.0:
				_fire_ring()
				state = State.RECOVER
				_state_t = 0.4
	position.x = clamp(position.x, CLAMP_X_MIN, CLAMP_X_MAX)
	position.y = clamp(position.y, CLAMP_Y_MIN, CLAMP_Y_MAX)
	_update_anim(delta)

func _neighbour_swinging() -> bool:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or not is_instance_valid(e) or e.state == State.DEAD:
			continue
		if e.state != State.TELEGRAPH and e.state != State.STRIKE and e.state != State.SWEEP:
			continue
		if position.distance_to(e.position) < HOLD_RADIUS:
			return true
	return false

func _begin_telegraph() -> void:
	# SUBJECT SEVEN arms its Triple Tap on the first telegraph of a
	# fresh sequence; the chain fires after each strike.
	if kind == Kind.BOSS2 and not _chain_armed:
		_chain_armed = true
		_chain = 2
		if not _sig_announced:
			_sig_announced = true
			if game != null:
				game.banner("SUBJECT SEVEN: TRIPLE TAP", 2.0)
	_tele_dur = RhythmManager.time_to_next_beat_ms() / 1000.0
	# Strike snaps to the next beat, never sooner than ~0.25 s.
	_tele_dur = max(_tele_dur, 0.25)
	state = State.TELEGRAPH
	_state_t = _tele_dur

func _resolve_strike() -> void:
	var player = game.player if game != null else null
	if player == null or not is_instance_valid(player):
		return
	var dist: float = player.position.distance_to(position)
	if dist > STRIKE_RANGE:
		if game != null:
			game.add_float("WHIFF", position + Vector2(0, -160), Color(0.55, 0.58, 0.65))
		return
	if player.check_parry_strike(self):
		return
	if player._dodge_timer > 0.0:
		return
	# The hit lands: damage, combo break, style cut, taunt.
	player.take_hit(int(STATS[kind]["dmg"]))
	_taunt_t = 1.2

func _update_boss_timers(delta: float) -> void:
	if kind == Kind.BOSS1:
		if state == State.CHASE or state == State.RECOVER:
			_sig_t -= delta
			if _sig_t <= 0.0:
				_sig_t = 7.0
				_start_sweep()
	elif kind == Kind.VEX:
		# Phase thresholds fire a Blast immediately, timer or not.
		var frac: float = float(hp) / float(max_hp)
		var phase := 0
		if frac <= 0.33:
			phase = 2
		elif frac <= 0.66:
			phase = 1
		if phase != boss_phase:
			boss_phase = phase
			emit_signal("boss_phase_changed", boss_phase + 1)
			_start_blast()
			return
		if state != State.BLAST:
			_blast_t -= delta
			if _blast_t <= 0.0:
				_start_blast()

func _start_sweep() -> void:
	state = State.SWEEP
	_state_t = max(RhythmManager.time_to_next_beat_ms() / 1000.0, 0.25)
	if not _sig_announced:
		_sig_announced = true
		if game != null:
			game.banner("DR. CLIPBOARD: ROPE SWEEP — DODGE OR PARRY", 2.0)

func _start_blast() -> void:
	state = State.BLAST
	_state_t = max(RhythmManager.time_to_next_beat_ms() / 1000.0, 0.25)
	_blast_t = 8.0
	if not _blast_announced:
		_blast_announced = true
		if game != null:
			game.banner("VEX: SPOTLIGHT BLAST — DODGE OR PARRY", 2.0)

func _fire_ring() -> void:
	if game == null:
		return
	if kind == Kind.BOSS1:
		game.add_ring(position + Vector2(0, -60), 300.0, 0.6, 14, self)
	elif kind == Kind.VEX:
		game.add_ring(position + Vector2(0, -60), 420.0, 0.7, 20, self)

# --- taking hits ---------------------------------------------------------------

# Returns true when the hit killed this enemy.
func take_hit(damage: int, judgement: int, from_pos: Vector2, opts: Dictionary = {}) -> bool:
	if state == State.DEAD:
		return false
	hp -= damage
	_flash_t = 0.12
	# Web knockback: (knock/18)*260 px/s; punch 18, kick 30, counter 24.
	# The caller passes the knock value in opts; default is a punch.
	_kvx = (float(opts.get("knock", 18.0)) / 18.0) * 260.0 * (1.0 if from_pos.x <= position.x else -1.0)
	if opts.has("stun"):
		apply_stun(float(opts["stun"]))
	if opts.has("flash"):
		_flash_t = max(_flash_t, float(opts["flash"]))
	if hp <= 0:
		_die()
		return true
	return false

func _die() -> void:
	state = State.DEAD
	_corpse_t = 0.0
	remove_from_group("enemies")
	_counter_label.visible = false
	_excl_label.visible = false
	_play_clip("knock", 1.0)
	emit_signal("enemy_died", self)

# --- animation -------------------------------------------------------------------

func _play_clip(clip: String, dur: float) -> void:
	if _sprite.frames == null or not _sprite.frames.has_animation(clip):
		return
	_current_clip = clip
	_sprite.animation = clip
	var natural := SheetFramesScript.natural_dur(String(STATS[kind]["sheet"]), clip)
	_sprite.speed_scale = natural / max(dur, 0.05) if natural > 0.0 else 1.0
	_sprite.frame = 0
	_sprite.playing = true

func _clip_dur(clip: String, beats: float) -> float:
	var natural := SheetFramesScript.natural_dur(String(STATS[kind]["sheet"]), clip)
	return max(0.25, min(natural, beats * RhythmManager.beat_dur_sec()))

func _update_anim(delta: float) -> void:
	_sprite.flip_h = facing == -1
	_sprite.offset.x = _ground_dx * (-1.0 if _sprite.flip_h else 1.0)
	# Hit flash: bright white silhouette for 0.12 s.
	if _flash_t > 0.0:
		_sprite.modulate = Color(2.0, 2.0, 2.0, 1.0)
	else:
		_sprite.modulate = STATS[kind]["tint"]
	# Telegraph prompt: gold COUNTER + red "!" over the enemy.
	var tele: bool = state == State.TELEGRAPH
	_counter_label.visible = tele
	_excl_label.visible = tele
	if tele:
		# Red flash at 10 Hz while telegraphing.
		var on: bool = int(OS.get_ticks_msec() / 100.0) % 2 == 0
		_sprite.modulate = Color(1.6, 0.4, 0.4, 1.0) if on else Color(1.0, 0.55, 0.55, 1.0)
	if state == State.DEAD:
		return
	if _taunt_t > 0.0:
		_set_clip("taunt")
	elif _stun_t > 0.0 or _flash_t > 0.0:
		_set_clip("hit")
	elif state == State.WINDUP:
		# Windup progress 0 -> 1 drives the clip frame.
		var prog := 0.85 * (1.0 - clamp(_state_t / _windup_max, 0.0, 1.0))
		_set_clip_frame("windup", prog)
	elif state == State.TELEGRAPH or state == State.BLAST or state == State.SWEEP:
		_set_clip_frame("windup", 0.99)
	elif state == State.STRIKE:
		_set_clip("upper" if kind == Kind.BRUISER else "punch")
	elif state == State.RECOVER:
		_set_clip("upper" if kind == Kind.BRUISER else "punch")
	elif state == State.CHASE:
		var moving := _vel.length() > 5.0
		if moving:
			if _current_clip != "walk":
				_current_clip = "walk"
				_sprite.animation = "walk"
				_sprite.playing = false
			var phase: float = fmod(_walk_dist / 28.0, 1.0)
			_sprite.frame = int(phase * 14.0) % 14
		else:
			_set_clip("idle")

func _set_clip(clip: String) -> void:
	if _current_clip == clip and _sprite.playing:
		return
	_current_clip = clip
	if _sprite.frames != null and _sprite.frames.has_animation(clip):
		_sprite.animation = clip
		_sprite.speed_scale = 1.0
		_sprite.playing = true

func _set_clip_frame(clip: String, progress: float) -> void:
	if _sprite.frames == null or not _sprite.frames.has_animation(clip):
		return
	if _current_clip != clip:
		_current_clip = clip
		_sprite.animation = clip
	_sprite.playing = false
	var count: int = SheetFramesScript.frame_count(String(STATS[kind]["sheet"]), clip)
	if count > 0:
		_sprite.frame = int(clamp(progress, 0.0, 1.0) * float(count - 1))
