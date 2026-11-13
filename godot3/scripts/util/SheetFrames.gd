extends Reference
# SLEEZE DISCO — SheetFrames (Godot 3.5 / GDScript).
#
# Builds SpriteFrames from the split sheet PNGs at runtime
# (tools/split_sheets.py). Frames are 512x256 POT canvases with the
# ground point at (256, 232) — 104 px below the texture centre — so the
# fighter node's origin is the feet (see Player/Enemy for the placement).
#
# Clip data mirrors ANIM_SHEETS in the web build (PORT_SPEC.md §13.1).
# Sheets that lack a clip fall back per CLIP_FALLBACK (web behaviour).
# Animations play at 24 fps; callers scale playback with speed_scale
# to hit the web clipDur formula (see Player.play_clip).

class_name SheetFrames

const SHEET_DIR := "res://assets/sheets/"
const FPS := 24.0

# clip -> [startFrame, frameCount] (verbatim from ANIM_SHEETS).
const CLIPS_FULL := {
	"idle": [0, 9], "walk": [9, 14], "punch": [23, 11], "kick": [34, 10],
	"throw": [44, 11], "windup": [55, 7], "hit": [62, 8], "knock": [70, 12],
	"getup": [82, 16], "block": [98, 6], "upper": [104, 10], "taunt": [114, 10],
	"hiphop": [124, 24], "headspin": [148, 8], "flair": [156, 10],
	"spinback": [166, 14], "sweep": [180, 12], "armada": [192, 12],
	"meialua": [204, 12], "spinflip": [216, 12],
}
const CLIPS_SUBSET := {
	"idle": [0, 9], "walk": [9, 14], "punch": [23, 11], "kick": [34, 10],
	"throw": [44, 11], "windup": [55, 7], "hit": [62, 8], "knock": [70, 12],
	"upper": [82, 10], "taunt": [92, 10],
}

# Which clips exist on each sheet (thug/dead have the 10-clip subset).
const SHEET_CLIPS := {
	"psxm": CLIPS_FULL,
	"psxw": CLIPS_FULL,
	"thug": CLIPS_SUBSET,
	"dead": CLIPS_SUBSET,
}

# Web CLIP_FALLBACK: a missing clip plays another clip's frames.
const CLIP_FALLBACK := {
	"hiphop": "idle", "headspin": "kick", "flair": "kick",
	"spinback": "kick", "sweep": "kick", "armada": "kick",
	"meialua": "kick", "spinflip": "kick", "getup": "idle",
	"block": "windup",
}

# Clips that loop when played (walk/idle/hiphop); the rest are one-shots.
const LOOPING := ["idle", "walk", "hiphop"]

static func frame_count(sheet_key: String, clip: String) -> int:
	var table: Dictionary = SHEET_CLIPS.get(sheet_key, CLIPS_FULL)
	var entry: Array = table.get(clip, [])
	if entry.empty() and CLIP_FALLBACK.has(clip):
		entry = table.get(CLIP_FALLBACK[clip], [])
	if entry.empty():
		return 0
	return int(entry[1])

# Natural duration of a clip at 24 fps, in seconds.
static func natural_dur(sheet_key: String, clip: String) -> float:
	return float(frame_count(sheet_key, clip)) / FPS

# Build the SpriteFrames for one sheet. Only the requested clips are
# loaded, so a fight holds player + live enemy sheets, not all five.
static func build(sheet_key: String, clips: Array) -> SpriteFrames:
	var frames := SpriteFrames.new()
	var table: Dictionary = SHEET_CLIPS.get(sheet_key, CLIPS_FULL)
	for clip in clips:
		var src_clip: String = clip
		var entry: Array = table.get(clip, [])
		if entry.empty() and CLIP_FALLBACK.has(clip):
			src_clip = CLIP_FALLBACK[clip]
			entry = table.get(src_clip, [])
		if entry.empty():
			push_warning("SheetFrames: no frames for " + sheet_key + "/" + clip)
			continue
		frames.add_animation(clip)
		frames.set_animation_speed(clip, FPS)
		frames.set_animation_loop(clip, clip in LOOPING)
		var count: int = int(entry[1])
		for i in range(count):
			var path := SHEET_DIR + sheet_key + "/" + src_clip + "_%03d.png" % i
			var tex: Texture = load(path)
			if tex == null:
				push_warning("SheetFrames: missing " + path)
				continue
			frames.add_frame(clip, tex)
	return frames

# All clips a sheet can play (used by the fighter to know what exists).
static func available_clips(sheet_key: String) -> Array:
	var table: Dictionary = SHEET_CLIPS.get(sheet_key, CLIPS_FULL)
	return table.keys()
