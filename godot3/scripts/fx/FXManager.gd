extends Node2D
class_name FXManager
const BeatData := preload("res://scripts/util/BeatData.gd")
# SLEEZE DISCO — FXManager (Godot 3.5 / GDScript, 2D).
#
# Port of web v7.6 FX (PORT_SPEC.md §1.5, §3.4, §13.2). One node, drawn
# above the fighters: dash ghosts, slashes, shockwave rings, impact
# rings, particle bursts, floating combat text (Label nodes).
# Baked-circle shadows live on the fighters themselves (see make_shadow).

const FLOAT_LIFE := 0.9
const FLOAT_RISE := 45.0
const PARTICLE_GRAVITY := 550.0
const GHOST_LIFE := 0.28
const SLASH_LIFE := 0.18

var game = null
var _float_font: DynamicFont = null  # 18px DejaVuSans-Bold for float labels

var _particles := []   # {p, v, life, max, col, r}
var _impact_rings := []  # {p, t, dur, max_r, heavy}
var _shock_rings := []   # {p, t, dur, max_r, dmg, owner, done}
var _ghosts := []      # {tex, p, flip, tint, scale, life, max}
var _slashes := []     # {p, t, max, dir}
var _floats := []      # Label nodes

func setup(p_game) -> void:
	game = p_game

# --- baked shadow (one per fighter; child of the fighter node, under the sprite) ---
static func make_shadow(width: float) -> Polygon2D:
	var pts := PoolVector2Array()
	var n := 24
	for i in range(n):
		var a := TAU * float(i) / float(n)
		pts.append(Vector2(cos(a) * width * 0.5, sin(a) * width * 0.18))
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.color = Color(0, 0, 0, 0.45)
	return poly

# --- particles -------------------------------------------------------------------

func hit_sparks(pos: Vector2, judgement: int) -> void:
	var count := 8
	var col := Color(1, 1, 1)
	if judgement == BeatData.Judgement.PERFECT:
		count = 16
		col = Color(1.0, 0.78, 0.24)
	elif judgement == BeatData.Judgement.GOOD:
		col = Color(0.0, 0.94, 1.0)
	_spawn_burst(pos, col, count, 240.0)
	add_slash(pos, 1)

func burst(pos: Vector2, col: Color, count: int) -> void:
	_spawn_burst(pos, col, count, 200.0)

func _spawn_burst(pos: Vector2, col: Color, count: int, speed: float) -> void:
	for i in range(count):
		var a := randf() * TAU
		var v := Vector2(cos(a), sin(a)) * speed * (0.5 + randf() * 0.7)
		_particles.append({
			"p": pos + Vector2(0, -60),
			"v": v,
			"life": 0.4 + randf() * 0.25,
			"max": 0.65,
			"col": col,
			"r": 2.0 + randf() * 2.5,
		})
	if _particles.size() > 240:
		_particles = _particles.slice(_particles.size() - 240, _particles.size() - 1)

# --- rings ------------------------------------------------------------------------

func impact_ring(pos: Vector2, heavy: bool, beat_dur: float) -> void:
	_impact_rings.append({
		"p": pos,
		"t": 0.0,
		"dur": max(beat_dur, 0.1),
		"max_r": 70.0 if heavy else 46.0,
		"heavy": heavy,
	})

func add_ring(pos: Vector2, max_r: float, dur: float, dmg: int, owner) -> void:
	_shock_rings.append({
		"p": pos, "t": 0.0, "dur": dur, "max_r": max_r,
		"dmg": dmg, "owner": owner, "done": false,
	})

func add_ghost(tex: Texture, pos: Vector2, flip: bool, tint: Color, p_scale: float) -> void:
	_ghosts.append({
		"tex": tex, "p": pos, "flip": flip, "tint": tint,
		"scale": p_scale, "life": GHOST_LIFE, "max": GHOST_LIFE,
	})

func add_slash(pos: Vector2, dir: int) -> void:
	_slashes.append({"p": pos + Vector2(0, -80), "t": 0.0, "max": SLASH_LIFE, "dir": dir})

# --- floats -------------------------------------------------------------------------

func add_float(text: String, pos: Vector2, col: Color) -> void:
	var lab := Label.new()
	lab.text = text
	lab.add_color_override("font_color", col)
	if _float_font == null:
		_float_font = DynamicFont.new()
		_float_font.font_data = load("res://assets/fonts/DejaVuSans-Bold.ttf")
		_float_font.size = 18
	lab.add_font_override("font", _float_font)
	var p := Vector2(clamp(pos.x, 70.0, 890.0), pos.y - float(_floats.size() % 3) * 22.0)
	lab.rect_position = p
	lab.set_meta("life", FLOAT_LIFE)
	add_child(lab)
	_floats.append(lab)

# --- update -------------------------------------------------------------------------

func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	# Particles.
	var i := _particles.size() - 1
	while i >= 0:
		var pt: Dictionary = _particles[i]
		pt["v"] = (pt["v"] as Vector2) + Vector2(0, PARTICLE_GRAVITY * delta)
		pt["p"] = (pt["p"] as Vector2) + (pt["v"] as Vector2) * delta
		pt["life"] = float(pt["life"]) - delta
		if float(pt["life"]) <= 0.0:
			_particles.remove(i)
		i -= 1
	# Impact rings.
	i = _impact_rings.size() - 1
	while i >= 0:
		_impact_rings[i]["t"] = float(_impact_rings[i]["t"]) + delta
		if float(_impact_rings[i]["t"]) >= float(_impact_rings[i]["dur"]):
			_impact_rings.remove(i)
		i -= 1
	# Ghosts.
	i = _ghosts.size() - 1
	while i >= 0:
		_ghosts[i]["life"] = float(_ghosts[i]["life"]) - delta
		if float(_ghosts[i]["life"]) <= 0.0:
			_ghosts.remove(i)
		i -= 1
	# Slashes.
	i = _slashes.size() - 1
	while i >= 0:
		_slashes[i]["t"] = float(_slashes[i]["t"]) + delta
		if float(_slashes[i]["t"]) >= float(_slashes[i]["max"]):
			_slashes.remove(i)
		i -= 1
	# Shockwave rings: expand, check the player, remove when spent.
	_update_shock_rings(delta)
	# Floats rise and fade.
	i = _floats.size() - 1
	while i >= 0:
		var lab: Label = _floats[i]
		if not is_instance_valid(lab):
			_floats.remove(i)
			i -= 1
			continue
		var life: float = float(lab.get_meta("life")) - delta
		lab.set_meta("life", life)
		lab.rect_position.y -= FLOAT_RISE * delta
		lab.modulate.a = clamp(life / FLOAT_LIFE, 0.0, 1.0)
		if life <= 0.0:
			lab.queue_free()
			_floats.remove(i)
		i -= 1
	update()

func _update_shock_rings(delta: float) -> void:
	var player = game.player if game != null else null
	var i := _shock_rings.size() - 1
	while i >= 0:
		var ring: Dictionary = _shock_rings[i]
		ring["t"] = float(ring["t"]) + delta
		var done: bool = bool(ring["done"])
		if float(ring["t"]) >= float(ring["dur"]):
			_shock_rings.remove(i)
			i -= 1
			continue
		if not done and player != null and is_instance_valid(player) and player.hp > 0:
			var r: float = (float(ring["t"]) / float(ring["dur"])) * float(ring["max_r"])
			var centre: Vector2 = player.position + Vector2(0, -60)
			var dist: float = centre.distance_to(ring["p"] as Vector2)
			if abs(dist - r) < 30.0:
				if player._parry_timer > 0.0:
					# Ring parry: the ring is consumed, the owner stuns.
					if player.check_parry_ring(ring):
						ring["done"] = true
				elif player._dodge_timer > 0.0:
					# Dodge: the ring passes through and stays live.
					pass
				else:
					ring["done"] = true
					player.take_hit(int(ring["dmg"]))
					if game != null:
						game.add_shake(12)
		i -= 1

# --- draw ---------------------------------------------------------------------------

func _draw() -> void:
	# Dash ghosts (under everything else in this layer).
	for g in _ghosts:
		var tex: Texture = g["tex"]
		if tex == null:
			continue
		var s: float = float(g["scale"])
		var a: float = 0.35 * clamp(float(g["life"]) / float(g["max"]), 0.0, 1.0)
		var tint: Color = g["tint"]
		tint.a = a
		var flip_sign := -1.0 if bool(g["flip"]) else 1.0
		draw_set_transform((g["p"] as Vector2) + Vector2(0, -104.0 * s), 0.0, Vector2(s * flip_sign, s))
		draw_texture(tex, Vector2(-256, -128), tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Slashes.
	for sl in _slashes:
		var frac: float = 1.0 - float(sl["t"]) / float(sl["max"])
		var c := Color(1.0, 0.78, 0.24, frac)
		var dir: int = int(sl["dir"])
		draw_arc(sl["p"] as Vector2, 42.0, -0.9 * dir, 0.9 * dir, 16, c, 4.0)
	# Shockwave rings (red, expanding).
	for ring in _shock_rings:
		var t: float = float(ring["t"]) / float(ring["dur"])
		var rr: float = t * float(ring["max_r"])
		var rc := Color(0.9, 0.2, 0.2, 1.0 - t * 0.5)
		draw_arc(ring["p"] as Vector2, rr, 0.0, TAU, 48, rc, 5.0)
	# Impact rings (on every hit; gold when heavy).
	for ir in _impact_rings:
		var t2: float = float(ir["t"]) / float(ir["dur"])
		var r2: float = t2 * float(ir["max_r"])
		var c2 := Color(1.0, 0.78, 0.24, 1.0 - t2) if bool(ir["heavy"]) else Color(1, 1, 1, 0.8 * (1.0 - t2))
		draw_arc(ir["p"] as Vector2, r2, 0.0, TAU, 40, c2, 3.0)
	# Particles.
	for pt in _particles:
		var frac3: float = clamp(float(pt["life"]) / float(pt["max"]), 0.0, 1.0)
		var c3: Color = pt["col"]
		c3.a = frac3
		draw_circle(pt["p"] as Vector2, float(pt["r"]), c3)
