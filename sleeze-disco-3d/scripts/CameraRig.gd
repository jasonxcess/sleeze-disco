extends Spatial
# Third-person chase camera on a SpringArm boom with collision.
# Free mode: pulled back + slightly high so the whole enemy ring reads.
# Lock-on (L): eases over the shoulder toward the target (stands in for aim).
# FOV scales with speed; dash kicks it; trauma-style shake.

var player
var yaw_node : Spatial
var pitch_node : Spatial
var arm : SpringArm
var cam : Camera
var yaw = 0.0
var pitch = -32.0
var lock = null
var lock_amt = 0.0
var fov_kick = 0.0
var trauma = 0.0
var _seed = 0.0

const FREE_LEN = 7.4
const FREE_PITCH = -32.0
const LOCK_LEN = 3.3
const LOCK_PITCH = -13.0
const BASE_FOV = 62.0

func _ready():
	yaw_node = Spatial.new(); add_child(yaw_node)
	pitch_node = Spatial.new(); yaw_node.add_child(pitch_node)
	arm = SpringArm.new()
	arm.spring_length = FREE_LEN
	arm.collision_mask = G.L_WORLD
	arm.margin = 0.15
	var sh = SphereShape.new(); sh.radius = 0.25
	arm.shape = sh
	pitch_node.add_child(arm)
	cam = Camera.new()
	cam.fov = BASE_FOV
	cam.near = 0.15
	cam.far = 60.0
	cam.current = true
	arm.add_child(cam)
	arm.add_excluded_object(player.get_rid())
	global_transform.origin = player.global_transform.origin + Vector3.UP * 1.45

func yaw_basis():
	return Basis(Vector3.UP, deg2rad(yaw))

func set_lock(t):
	lock = t

func kick_fov(a):
	fov_kick = max(fov_kick, a)

func shake(a):
	trauma = min(1.0, trauma + a)

func _process(delta):
	var rd = G.real_delta(delta) if not get_tree().paused else delta
	var cx = 0.0
	var cy = 0.0
	if player.input_override == null:
		cx = Input.get_action_strength("cam_right") - Input.get_action_strength("cam_left")
		cy = Input.get_action_strength("cam_down") - Input.get_action_strength("cam_up")
	elif player.input_override.has("cam"):
		cx = player.input_override.cam.x; cy = player.input_override.cam.y
	var locked = lock != null and is_instance_valid(lock) and not lock.dead
	lock_amt = move_toward(lock_amt, 1.0 if locked else 0.0, rd * 2.5)
	var e = lock_amt * lock_amt * (3.0 - 2.0 * lock_amt)
	yaw -= cx * 150.0 * rd
	var p_target = FREE_PITCH
	pitch = clamp(pitch - cy * 80.0 * rd, -60.0, -8.0)
	var follow = player.global_transform.origin + Vector3.UP * 1.45
	if locked:
		var tp = lock.global_transform.origin
		var d = tp - player.global_transform.origin
		d.y = 0
		if d.length() > 0.1:
			# camera behind the player, looking at the target, over the right shoulder
			var want_yaw = rad2deg(atan2(-d.x, -d.z))
			yaw = rad2deg(lerp_angle(deg2rad(yaw), deg2rad(want_yaw), min(1.0, rd * 4.0 * e)))
		follow = follow.linear_interpolate((player.global_transform.origin + tp) * 0.5 + Vector3.UP * 1.3, 0.25 * e)
		pitch = lerp(pitch, LOCK_PITCH, min(1.0, rd * 3.0 * e))
	elif lock_amt <= 0.0 and abs(cy) < 0.1:
		pitch = lerp(pitch, p_target, min(1.0, rd * 1.5))
	global_transform.origin = global_transform.origin.linear_interpolate(follow, min(1.0, rd * 9.0))
	yaw_node.rotation_degrees.y = yaw
	pitch_node.rotation_degrees.x = pitch
	arm.spring_length = lerp(FREE_LEN, LOCK_LEN, e)
	arm.translation.x = 0.75 * e
	# FOV from ground speed + dash kick
	fov_kick = move_toward(fov_kick, 0.0, rd * 22.0)
	cam.fov = lerp(cam.fov, BASE_FOV + clamp(player.speed, 0, 9) * 1.3 + fov_kick - e * 6.0, min(1.0, rd * 8.0))
	# shake
	trauma = max(0.0, trauma - rd * 1.8)
	_seed += rd * 40.0
	var s = trauma * trauma
	cam.h_offset = s * 0.25 * sin(_seed * 1.7)
	cam.v_offset = s * 0.2 * sin(_seed * 2.3 + 1.0)
	cam.rotation_degrees.z = s * 3.0 * sin(_seed * 1.3 + 2.0)
