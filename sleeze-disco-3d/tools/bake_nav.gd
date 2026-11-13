extends SceneTree
# Offline navmesh bake for the arena (run headless):
#   godot --path . --script res://tools/bake_nav.gd
# Builds the arena (club collision + riser/steps/ramp), bakes a NavigationMesh
# from the static colliders and saves res://data/arena_nav.tres.

func _init():
	call_deferred("_go")

func _go():
	var arena = load("res://scenes/Main.tscn").instance()
	arena.set_meta("nav_bake", true)
	get_root().add_child(arena)
	for i in range(8):
		yield(self, "physics_frame")
	var nm = NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.cell_size = 0.15
	nm.cell_height = 0.1
	nm.agent_radius = 0.4
	nm.agent_height = 1.7
	nm.agent_max_climb = 0.3
	nm.agent_max_slope = 40.0
	nm.region_min_size = 4.0
	nm.filter_low_hanging_obstacles = true
	nm.filter_ledge_spans = true
	nm.filter_walkable_low_height_spans = true
	NavigationMeshGenerator.bake(nm, arena)
	print("NAV polys=", nm.get_polygon_count(), " verts=", nm.get_vertices().size())
	var err = ResourceSaver.save("res://data/arena_nav.tres", nm)
	print("NAV saved err=", err)
	quit()
