extends Node
# SLEEZE DISCO 2D — line-flushed boot log (autoload "BootLog").
#
# Same approach as the 3D build's G.blog: every line reopens, appends and
# closes the file, so if the Vita kills the app mid-boot the last line on
# disk is the last thing that finished. Written to
#   ux0:data/SLZD00001/boot.log   (Vita; falls back to user://boot.log)
# Each line carries ms since launch plus texture / static memory so an
# out-of-memory death during asset load shows up as the numbers climbing
# and then stopping.

const VITA_DIR := "ux0:data/SLZD00001"
const DESKTOP_OS := ["X11", "Windows", "OSX", "Server", "Android", "iOS", "HTML5", "UWP"]

var log_path := ""
var _frames_logged := 0

func _init() -> void:
	# _init (not _ready) so the log exists before any other autoload or the
	# main scene starts loading textures.
	var d := Directory.new()
	# On desktop "ux0:data/..." is just a relative path and would drop a
	# stray ux0:data folder into the project (that is how the 3D build's
	# boot.log got committed), so only try it off the known desktop OSes.
	var bases := ["user:/"]
	if not OS.get_name() in DESKTOP_OS:
		bases.push_front(VITA_DIR)
	for base in bases:
		if base != "user:/":
			d.make_dir_recursive(base)
		var path: String = base + "/boot.log"
		var f := File.new()
		if f.open(path, File.WRITE) == OK:
			f.store_line("SLEEZE DISCO 2D boot log — Godot %s, %s" % [
				Engine.get_version_info().get("string", "?"), OS.get_name()])
			f.close()
			log_path = path
			break
	blog("BootLog ready, log=" + log_path)

func _process(_delta: float) -> void:
	# Log the first few drawn frames, then go quiet.
	if _frames_logged < 3:
		_frames_logged += 1
		blog("frame %d drawn" % _frames_logged)
	else:
		set_process(false)

func mem() -> String:
	var tex := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	var vid := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	var stat := Performance.get_monitor(Performance.MEMORY_STATIC)
	return "tex=%.1fMB vid=%.1fMB static=%.1fMB" % [
		tex / 1048576.0, vid / 1048576.0, stat / 1048576.0]

func blog(msg: String) -> void:
	var line := "[%6d ms] %s | %s" % [OS.get_ticks_msec(), msg, mem()]
	print(line)
	if log_path == "":
		return
	var f := File.new()
	if f.open(log_path, File.READ_WRITE) == OK:
		f.seek_end()
		f.store_line(line)
		f.close()
