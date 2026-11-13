// SLEEZE DISCO v2 — FXManager implementation.
#include "fx_manager.hpp"
#include <cstdlib>
#include <cmath>

namespace sleeze {

FXManager::FXManager()
    : free_count_(MAX_TOTAL), tex_spark_(nullptr), tex_gold_(nullptr),
      tex_cyan_(nullptr), tex_red_(nullptr), tex_shadow_(nullptr) {
    for (int i = 0; i < MAX_TOTAL; ++i) {
        pool_[i].alive = false;
        freelist_[i] = MAX_TOTAL - 1 - i;
    }
    for (int i = 0; i < MAX_SHADOWS; ++i) shadows_[i].active = false;
}

void FXManager::set_textures(vita2d_texture* spark, vita2d_texture* glow_gold,
                             vita2d_texture* glow_cyan, vita2d_texture* glow_red,
                             vita2d_texture* shadow_tex) {
    tex_spark_ = spark; tex_gold_ = glow_gold;
    tex_cyan_ = glow_cyan; tex_red_ = glow_red; tex_shadow_ = shadow_tex;
}

int FXManager::spawn(int tex, float x, float y, float vx, float vy,
                     float life, float size, uint32_t color) {
    int idx = -1;
    if (free_count_ > 0) {
        idx = freelist_[--free_count_];
    } else {
        // Pool full: recycle the oldest live particle (index 0 scan).
        for (int i = 0; i < MAX_TOTAL; ++i) {
            if (pool_[i].alive) { idx = i; break; }
        }
        if (idx < 0) return -1;
    }
    Particle& p = pool_[idx];
    p.alive = true; p.tex = tex;
    p.x = x; p.y = y; p.vx = vx; p.vy = vy;
    p.life = life; p.max_life = life; p.size = size; p.color = color;
    return idx;
}

void FXManager::hit_sparks(float x, float y, Judgement j) {
    const int count = (j == Judgement::PERFECT) ? 24 : (j == Judgement::GOOD) ? 14 : 8;
    const uint32_t col = (j == Judgement::PERFECT) ? palette::GOLD
                         : (j == Judgement::GOOD) ? palette::CYAN : palette::WHITE;
    const int tex = (j == Judgement::PERFECT) ? 1 : 0;
    for (int i = 0; i < count; ++i) {
        const float a = float(rand()) / float(RAND_MAX) * 6.2831853f;
        const float sp = 90.0f + float(rand() % 220);
        spawn(tex, x, y, std::cos(a) * sp, std::sin(a) * sp - 60.0f,
              0.28f + float(rand() % 20) / 100.0f, 6.0f + float(rand() % 10), col);
    }
}

void FXManager::takedown_burst(float x, float y) {
    // Hard cap: exactly MAX_PER_EFFECT, no more.
    for (int i = 0; i < MAX_PER_EFFECT; ++i) {
        const float a = float(i) / float(MAX_PER_EFFECT) * 6.2831853f;
        const float sp = 140.0f + float(rand() % 260);
        spawn(1, x, y, std::cos(a) * sp, std::sin(a) * sp,
              0.5f + float(rand() % 30) / 100.0f, 8.0f + float(rand() % 12), palette::GOLD);
    }
}

void FXManager::beat_ring(float x, float y) {
    // One expanding glow: a single particle with negative "velocity"
    // faked by growing size as life falls (handled in draw by life01).
    spawn(2, x, y, 0.0f, 0.0f, 0.45f, 26.0f, palette::CYAN);
}

void FXManager::dust(float x, float y, int count) {
    if (count > MAX_PER_EFFECT) count = MAX_PER_EFFECT;
    for (int i = 0; i < count; ++i) {
        const float vx = float(rand() % 120) - 60.0f;
        spawn(0, x + float(rand() % 40) - 20.0f, y, vx, -20.0f - float(rand() % 40),
              0.4f, 5.0f + float(rand() % 6), palette::GREY);
    }
}

void FXManager::set_shadow(int slot, float x, float y, float base_w, float height01) {
    if (slot < 0 || slot >= MAX_SHADOWS) return;
    Shadow& s = shadows_[slot];
    s.active = true; s.x = x; s.y = y; s.base_w = base_w; s.height01 = height01;
}

void FXManager::clear_shadows() {
    for (int i = 0; i < MAX_SHADOWS; ++i) shadows_[i].active = false;
}

void FXManager::update(float dt) {
    for (int i = 0; i < MAX_TOTAL; ++i) {
        Particle& p = pool_[i];
        if (!p.alive) continue;
        p.life -= dt;
        if (p.life <= 0.0f) {
            p.alive = false;
            freelist_[free_count_++] = i;
            continue;
        }
        p.vy += 320.0f * dt; // sparks arc down; dust barely falls
        p.x += p.vx * dt;
        p.y += p.vy * dt;
        p.vx *= (1.0f - 1.6f * dt);
    }
}

void FXManager::draw() {
    // Baked shadows first (under everything): shrink + fade with height.
    if (tex_shadow_) {
        for (int i = 0; i < MAX_SHADOWS; ++i) {
            const Shadow& s = shadows_[i];
            if (!s.active) continue;
            const float h = s.height01 < 0.0f ? 0.0f : (s.height01 > 1.0f ? 1.0f : s.height01);
            const float w = s.base_w * (1.0f - 0.45f * h);
            const float alpha = 1.0f - 0.6f * h;
            const uint8_t a = uint8_t(200.0f * alpha);
            const uint32_t col = RGBA8(0, 0, 0, a);
            vita2d_draw_texture_tint_scale(tex_shadow_, s.x - w / 2.0f, s.y - 10.0f,
                                           w / 200.0f, (w * 0.24f) / 48.0f, col);
        }
    }
    // Particles: flat neon, unlit. Alpha fades with remaining life.
    for (int i = 0; i < MAX_TOTAL; ++i) {
        const Particle& p = pool_[i];
        if (!p.alive) continue;
        vita2d_texture* t = tex_spark_;
        if (p.tex == 1) t = tex_gold_;
        else if (p.tex == 2) t = tex_cyan_;
        else if (p.tex == 3) t = tex_red_;
        if (!t) continue;
        const float life01 = p.life / p.max_life;
        const float grow = (p.tex == 2) ? (1.0f + (1.0f - life01) * 3.0f) : 1.0f;
        const float s = p.size * grow;
        const uint32_t base = p.color;
        const uint8_t a = uint8_t(255.0f * life01);
        // RGBA8 layout: alpha is the top byte; keep RGB, replace alpha.
        const uint32_t col = (base & 0x00FFFFFFu) | (uint32_t(a) << 24);
        vita2d_draw_texture_tint_scale(t, p.x - s / 2.0f, p.y - s / 2.0f,
                                       s / 64.0f, s / 64.0f, col);
    }
}

int FXManager::live_count() const {
    int n = 0;
    for (int i = 0; i < MAX_TOTAL; ++i) if (pool_[i].alive) ++n;
    return n;
}

} // namespace sleeze
