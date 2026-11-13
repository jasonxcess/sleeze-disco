extends Node2D
# SLEEZE DISCO — StageLayer (Godot 3.5 / GDScript, 2D).
#
# Draws the dancefloor + EQ bars between the club backdrops and the
# fighters (PORT_SPEC.md §13.2). Beat-reactive: the floor grid and EQ
# bars pulse with the beat; Fever Rush pushes the amplitude x1.6.

var game = null

func setup(p_game) -> void:
	game = p_game

func _process(_delta: float) -> void:
	update()

func _draw() -> void:
	var pulse := 0.0
	var rush := false
	var beat_ix := 0
	if game != null:
		pulse = game.pulse()
		rush = game.is_rushing()
		beat_ix = RhythmManager.beat_index
	# Dancefloor fill #0B061A from y=310.
	draw_rect(Rect2(0, 310, 960, 234), Color(0.043, 0.024, 0.102))
	var line_col := Color(1.0, 0.2, 0.8, 0.22 + pulse * 0.25)
	# Horizontal lines every 36 px, y 310..490.
	var y := 310
	while y <= 490:
		draw_line(Vector2(0, y), Vector2(960, y), line_col, 1.0)
		y += 36
	# Converging verticals from the vanishing point (480, 310).
	for i in range(-6, 7):
		draw_line(Vector2(480 + i * 40, 310), Vector2(480 + i * 160, 544), line_col, 1.0)
	# 16 EQ bars along the bottom, beat-reactive (Rush x1.6).
	var amp := 1.6 if rush else 1.0
	for i in range(16):
		var wob := 0.5 + 0.5 * sin(float(i) * 2.3 + float(beat_ix) * 0.9)
		var h := (12.0 + 30.0 * pulse * amp) * (0.55 + 0.45 * wob)
		var col := Color(1.0, 0.78, 0.24, 0.75) if i % 4 == 0 else Color(1.0, 0.2, 0.8, 0.7)
		draw_rect(Rect2(18 + i * 58, 544 - h - 4, 40, h), col)
