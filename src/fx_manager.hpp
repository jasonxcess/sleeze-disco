// SLEEZE DISCO v2 — FXManager (raw C++ / VitaSDK).
//
// Particles and baked shadows, under Shawn's hard rules:
//   * MAX 50 particles per effect. Not a guideline — the pool refuses
//     more, and the oldest particle is recycled first if a burst
//     overflows. Total live particles can never exceed 150.
//   * UNLIT flat neon textures only (vita2d draws unlit; no lights,
//     no PBR, no shaders, no shadow-casting anything).
//   * NO dynamic shadows. Every fighter gets one baked soft shadow
//     circle (a radial-gradient texture) drawn under them. When the
//     fighter jumps, the circle shrinks and fades with height —
//     that sells the jump with zero lighting cost.
//   * Zero heap allocation after construction: one fixed pool,
//     freelist indices, no std::vector in update/draw.
#pragma once
#include "game.hpp"
#include <vita2d.h>

namespace sleeze {

class FXManager {
public:
    static constexpr int MAX_PER_EFFECT = 50;
    static constexpr int MAX_TOTAL = 150; // 3 effects' worth, hard cap
    static constexpr int MAX_SHADOWS = 8; // fighters on screen at once

    struct Particle {
        bool alive = false;
        float x = 0, y = 0;       // screen space
        float vx = 0, vy = 0;
        float life = 0, max_life = 1;
        float size = 8;
        uint32_t color = palette::WHITE;
        int tex = 0;              // 0 spark, 1 glow gold, 2 glow cyan, 3 glow red
    };

    struct Shadow {
        bool active = false;
        float x = 0, y = 0;       // floor position (screen space)
        float base_w = 120;       // width on the ground
        float height01 = 0;       // 0 grounded .. 1 jump apex
    };

    FXManager();
    // Textures must be loaded by the game loop first (vita2d_load_*).
    // Pass nullptr for any texture you don't use; that effect is skipped.
    void set_textures(vita2d_texture* spark, vita2d_texture* glow_gold,
                      vita2d_texture* glow_cyan, vita2d_texture* glow_red,
                      vita2d_texture* shadow_tex);

    // ---- spawners: each caps at MAX_PER_EFFECT live particles ----
    void hit_sparks(float x, float y, Judgement j);   // punch/kick impact
    void takedown_burst(float x, float y);            // 50 gold sparks
    void beat_ring(float x, float y);                 // expanding glow on the beat
    void dust(float x, float y, int count = 8);       // landing / dodge dust

    // ---- baked shadows: one per fighter, slot 0 = the player ----
    void set_shadow(int slot, float x, float y, float base_w, float height01);
    void clear_shadows();

    void update(float dt); // integrate + kill dead particles
    void draw();           // shadows first, then particles (additive feel via tint)

    int live_count() const;

private:
    int spawn(int tex, float x, float y, float vx, float vy,
              float life, float size, uint32_t color);
    Particle pool_[MAX_TOTAL];
    int freelist_[MAX_TOTAL];
    int free_count_;
    Shadow shadows_[MAX_SHADOWS];
    vita2d_texture* tex_spark_;
    vita2d_texture* tex_gold_;
    vita2d_texture* tex_cyan_;
    vita2d_texture* tex_red_;
    vita2d_texture* tex_shadow_;
};

} // namespace sleeze
