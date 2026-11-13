// SLEEZE DISCO v2 — RhythmManager implementation.
#include "rhythm_manager.hpp"
#include <psp2/kernel/processmgr.h>
#include <cmath>

namespace sleeze {

namespace {
// Monotonic microsecond clock. Never the frame counter.
inline uint64_t now_us() { return sceKernelGetProcessTimeWide(); }
}

RhythmManager::RhythmManager()
    : bpm_(120), start_us_(0), latency_ms_(0.0), playing_(false), last_beat_(-1) {}

void RhythmManager::start(int bpm, uint64_t start_us) {
    bpm_ = bpm > 0 ? bpm : 120;
    start_us_ = start_us;
    playing_ = true;
    last_beat_ = -1;
}

void RhythmManager::stop() { playing_ = false; }

void RhythmManager::set_bpm(int bpm) {
    if (bpm > 0) bpm_ = bpm;
}

double RhythmManager::song_time_sec() const {
    if (!playing_) return 0.0;
    const double us = double(now_us() - start_us_) - latency_ms_ * 1000.0;
    return us / 1000000.0;
}

int RhythmManager::beat_index() const {
    const double t = song_time_sec();
    if (t < 0.0) return -1; // count-in: no beat yet
    return int(t / beat_length_sec());
}

double RhythmManager::beat_phase01() const {
    const double t = song_time_sec();
    if (t < 0.0) return 0.0;
    const double bl = beat_length_sec();
    const double ph = std::fmod(t, bl) / bl;
    return ph < 0.0 ? ph + 1.0 : ph;
}

double RhythmManager::ms_to_nearest_beat() const {
    const double bl_ms = beat_length_sec() * 1000.0;
    const double t_ms = song_time_sec() * 1000.0;
    double ph = std::fmod(t_ms, bl_ms);
    if (ph < 0.0) ph += bl_ms;
    if (ph > bl_ms * 0.5) return ph - bl_ms; // late side reads negative
    return ph;                               // early side reads positive
}

double RhythmManager::time_to_next_beat() const {
    const double bl = beat_length_sec();
    const double t = song_time_sec();
    if (t < 0.0) return -t;
    return bl - std::fmod(t, bl);
}

Judgement RhythmManager::judge_now() const {
    double ms = ms_to_nearest_beat();
    if (ms < 0.0) ms = -ms;
    if (ms <= PERFECT_MS) return Judgement::PERFECT;
    if (ms <= GOOD_MS) return Judgement::GOOD;
    return Judgement::OFFBEAT;
}

AttackResult RhythmManager::judge_attack(int base_damage, bool perfect_strikes_unlocked) const {
    AttackResult r;
    r.judgement = judge_now();
    r.multiplier = judgement_multiplier(r.judgement);
    r.base_damage = base_damage;
    r.ms_off_beat = ms_to_nearest_beat();
    int dmg = int(base_damage * r.multiplier + 0.5f);
    if (perfect_strikes_unlocked && r.judgement == Judgement::PERFECT) dmg += 2;
    r.damage = dmg;
    return r;
}

bool RhythmManager::poll_beat_edge() {
    if (!playing_) return false;
    const int b = beat_index();
    if (b != last_beat_ && b >= 0) {
        last_beat_ = b;
        return true;
    }
    return false;
}

} // namespace sleeze
