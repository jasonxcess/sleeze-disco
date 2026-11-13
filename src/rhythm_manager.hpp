// SLEEZE DISCO v2 — RhythmManager (raw C++ / VitaSDK).
//
// Tracks a song's BPM and turns the audio clock into beat windows that
// the attack animation state machine consumes. Lightweight by design:
// no heap allocation after construction, no per-frame objects, all math
// is a few doubles. The audio clock (sceKernelGetProcessTimeWide, a
// monotonic microsecond counter) is the master clock — never the frame
// counter, so a dropped frame can never knock the beat off.
//
// Windows (Shawn's spec):
//   PERFECT  +/-60 ms   -> 1.5x damage
//   GOOD     +/-120 ms  -> 1.1x damage  (the +/-120 ms input tolerance)
//   OFFBEAT  beyond that -> 1.0x, normal hit, NEVER a penalty.
// Off-beat is a real judgement, not a miss: mashing still lands hits.
#pragma once
#include "game.hpp"

namespace sleeze {

class RhythmManager {
public:
    // Windows in milliseconds. Tunable per-song / per-difficulty.
    static constexpr double PERFECT_MS = 60.0;
    static constexpr double GOOD_MS = 120.0; // aligned to Shawn's latest spec (was 100)

    RhythmManager();

    // Start a song. bpm = the track's BPM, start_us = the process-time
    // (microseconds, from sceKernelGetProcessTimeWide) at which beat 0
    // lands. Call once, right when the audio thread starts the track.
    void start(int bpm, uint64_t start_us);
    void stop();

    // Audio latency calibration (ms). Positive = the speakers lag the
    // clock, so beats are judged that much later. Tune once per device
    // from the in-game calibration screen; 0 is fine on Vita speakers.
    void set_latency_ms(double ms) { latency_ms_ = ms; }
    double latency_ms() const { return latency_ms_; }

    void set_bpm(int bpm);
    int bpm() const { return bpm_; }
    bool playing() const { return playing_; }

    // ---- readouts, all cheap, all callable every frame ----
    double beat_length_sec() const { return 60.0 / double(bpm_); }
    // Seconds since beat 0 (song time, latency-corrected).
    double song_time_sec() const;
    // Whole beats elapsed since beat 0.
    int beat_index() const;
    // 0.0..1.0 inside the current beat. 0 = exactly on the beat.
    double beat_phase01() const;
    // Signed ms to the NEAREST beat: negative = early, positive = late.
    double ms_to_nearest_beat() const;
    // Seconds until the next beat boundary (for scheduling spawns).
    double time_to_next_beat() const;

    // ---- judgement: the call the attack state machine makes ----
    // Judge the CURRENT instant (call it on the exact frame the player
    // presses punch/kick/throw). Returns the judgement + multiplier +
    // damage for a base damage value.
    AttackResult judge_attack(int base_damage, bool perfect_strikes_unlocked) const;
    Judgement judge_now() const;

    // Beat-edge detector: call once per frame. Returns true exactly once
    // per beat, on the first frame after a beat boundary. Use it for the
    // beat pulse, idle bob, enemy spawns and HUD flashes. Zero alloc.
    bool poll_beat_edge();

private:
    int bpm_;
    uint64_t start_us_;
    double latency_ms_;
    bool playing_;
    int last_beat_;
};

} // namespace sleeze
