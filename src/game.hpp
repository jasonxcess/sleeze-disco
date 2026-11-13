// SLEEZE DISCO v2 — shared types (raw C++ / VitaSDK, no engine).
// One header, no dependencies beyond the Vita SDK + stdint.
// All hot-path structs are plain data: no virtuals, no heap in update().
#pragma once
#include <stdint.h>

namespace sleeze {

// ---- rhythm judgement (matches the design doc + the shipped v1 loop) ----
// PERFECT window +/-60 ms  -> 1.5x damage.  GOOD window +/-120 ms (the
// input tolerance Shawn specced) -> 1.1x.  Anything later than that still
// lands as a normal hit at 1.0x: off-beat hits are NEVER penalised,
// mashing still looks like a fight scene and timing pays on top.
enum class Judgement : uint8_t { OFFBEAT = 0, GOOD = 1, PERFECT = 2 };

inline float judgement_multiplier(Judgement j) {
    switch (j) {
        case Judgement::PERFECT: return 1.5f;
        case Judgement::GOOD:    return 1.1f;
        default:                 return 1.0f;
    }
}
inline const char* judgement_text(Judgement j) {
    switch (j) {
        case Judgement::PERFECT: return "PERFECT!";
        case Judgement::GOOD:    return "GOOD";
        default:                 return "HIT";
    }
}

// Result handed to the attack animation state machine on every swing.
struct AttackResult {
    Judgement judgement;
    float multiplier;   // 1.0 / 1.1 / 1.5
    int base_damage;
    int damage;         // base * multiplier (+ Perfect Strikes bonus)
    double ms_off_beat; // signed: <0 early, >0 late, 0 = dead on
};

// Flat neon palette. Everything is UNLIT (vita2d draws textures unlit by
// default): these are plain vertex/texture colours, no lights, no PBR,
// no shaders. One palette, used by HUD, particles and prompts alike.
namespace palette {
    // vita2d RGBA8(r,g,b,a) packs as 0xAABBGGRR (alpha in the top byte).
    static constexpr uint32_t WHITE  = 0xFFFFFFFFu; // RGBA8(255,255,255,255)
    static constexpr uint32_t GOLD   = 0xFF3CC8FFu; // RGBA8(255,200,60,255)
    static constexpr uint32_t RED    = 0xFF3232E6u; // RGBA8(230,50,50,255)
    static constexpr uint32_t CYAN   = 0xFFFFDC3Cu; // RGBA8(60,220,255,255)
    static constexpr uint32_t PINK   = 0xFFB450FFu; // RGBA8(255,80,180,255)
    static constexpr uint32_t PURPLE = 0xFFFF5096u; // RGBA8(150,80,255,255)
    static constexpr uint32_t GREEN  = 0xFF78E650u; // RGBA8(80,230,120,255)
    static constexpr uint32_t GREY   = 0xFF968C8Cu; // RGBA8(140,140,150,255)
    static constexpr uint32_t BLACK  = 0xFF000000u; // RGBA8(0,0,0,255)
} // namespace palette

// Vita screen.
static constexpr int SCREEN_W = 960;
static constexpr int SCREEN_H = 544;

// Song table (BPMs from the design doc).
struct SongDef {
    const char* name;
    int bpm;
    int root_midi; // bass root for the synth generator
    int style;     // 0 alley, 1 dive bar, 2 idol
};
static constexpr SongDef SONGS[3] = {
    {"NEON ALLEY", 100, 45, 0},
    {"DIVE BAR",   120, 41, 1},
    {"VEX - IDOL", 140, 43, 2},
};

} // namespace sleeze
