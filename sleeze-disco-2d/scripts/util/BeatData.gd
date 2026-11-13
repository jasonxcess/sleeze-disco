extends Reference
# SLEEZE DISCO — BeatData (Godot 3.5 / GDScript).
#
# Shared beat constants: the Judgement enum + the v7.6 TRACKS table.
# These live in a plain script — NOT in the RhythmManager autoload —
# on purpose: game scripts cannot resolve the autoload singleton's
# constants at compile time when the game boots (the autoload identifier
# only exists in the editor's script server, so `RhythmManager.Judgement`
# / `RhythmManager.TRACKS` fail to parse at game-boot time and the whole
# preload chain collapses). Access is by preload (`const BeatData :=
# preload("res://scripts/util/BeatData.gd")`) — path-based, no global
# registry needed. Function calls (judge_attack, play_blip,
# beat_dur_sec, load_track, ...) stay on the autoload — those are dynamic
# calls resolved at runtime from the live node.
#
# Values MUST match the web v7.6 build (PORT_SPEC.md §1.2, §8).
# Judgement order is load-bearing: MISS=0, GOOD=1, PERFECT=2, HIT=3.

enum Judgement { MISS, GOOD, PERFECT, HIT }

const PERFECT_MS := 65.0
const GOOD_MS := 130.0

const MULT_PERFECT := 1.5
const MULT_GOOD := 1.1
const MULT_HIT := 1.0
const MULT_PARRY_MISS := 0.6

# v7.6 TRACKS (PORT_SPEC.md §8): BPM preset + audio loop. Bass/lead patterns
# live in tools/render_tracks.py, which rendered these loops from them.
# "sleezetroit" is Shawn's own song (100 BPM, first beat 0.296 s) — the
# full MP3, not a 60 s loop. Chapter 1 runs on it; "myluva" stays as the
# fallback if the MP3 fails to load (same BPM, same chapter).
const TRACKS := {
	"myluva":     {"name": "MY LUVA",      "bpm": 100, "genre": "FUNK",
	               "ogg": "res://assets/audio/bgm_myluva.ogg"},
	"sleezetroit": {"name": "SLEEZETROIT", "bpm": 100, "genre": "FUNK",
	               "mp3": "res://assets/audio/sleezetroit.mp3",
	               "first_beat_ms": 296.0, "fallback": "myluva"},
	"bigscreen":  {"name": "BIG SCREEN",   "bpm": 110, "genre": "FUNK",
	               "ogg": "res://assets/audio/bgm_bigscreen.ogg"},
	"dceased":    {"name": "DCEASED",      "bpm": 120, "genre": "HOUSE",
	               "ogg": "res://assets/audio/bgm_dceased.ogg"},
	"foolmeonce": {"name": "FOOL ME ONCE", "bpm": 130, "genre": "HOUSE",
	               "ogg": "res://assets/audio/bgm_foolmeonce.ogg"},
	"shittalkin": {"name": "SHIT TALKIN",  "bpm": 140, "genre": "DARK DISCO",
	               "ogg": "res://assets/audio/bgm_shittalkin.ogg"},
}
