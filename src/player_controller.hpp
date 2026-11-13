// SLEEZE DISCO v2 — PlayerController (raw C++ / VitaSDK).
//
// Top-down / isometric 2.5D movement + collision, built for the Vita's
// memory budget. The fight happens on an X/Z ground plane; Y is a
// SIMULATED vertical axis (jump height above the floor), not a third
// movement axis. The camera is fixed isometric, so "up" on the stick
// is -Z on the plane, rotated by the camera yaw.
//
// Low-memory rules enforced here:
//   * No heap allocation in update() — all state is member data.
//   * No std::vector in the hot path: colliders are a fixed array.
//   * Axis-separated collision: move X, resolve, move Z, resolve.
//     One pass, no solver iterations, no ghost vertices.
//   * Input is one struct filled per frame from SceCtrlData; the
//     controller never touches the pad itself (testable on PC).
#pragma once
#include <stdint.h>

namespace sleeze {

// Per-frame input, filled by the game loop from SceCtrlData.
// move_x / move_z are -1..1 in CAMERA space (up = -Z). Buttons are
// edge-triggered "pressed this frame" flags, computed by the caller.
struct PlayerInput {
    float move_x = 0.0f; // camera-right
    float move_z = 0.0f; // camera-forward (up on the stick = -1)
    bool jump_pressed = false;
    bool punch_pressed = false;
    bool kick_pressed = false;
    bool throw_pressed = false;
    bool dodge_pressed = false;
    bool counter_pressed = false;
    bool takedown_pressed = false;
};

// Static world colliders: axis-aligned boxes on the X/Z plane.
// The arena floor is the bounds rect; boxes are bar counters, stages,
// speaker stacks — things you walk around, never through.
struct AABB {
    float min_x, min_z, max_x, max_z;
};

class PlayerController {
public:
    enum class State : uint8_t {
        GROUNDED = 0, JUMPING, FALLING, ATTACKING, AIR_ATTACK, DODGING, HURT
    };

    // Tuning, all in game units (1 unit ~= 1 pixel at 960x544).
    static constexpr float WALK_SPEED = 300.0f;   // units / sec
    static constexpr float DODGE_SPEED = 720.0f;
    static constexpr float DODGE_TIME = 0.22f;    // sec of i-frames
    static constexpr float DODGE_COOLDOWN = 0.55f;
    static constexpr float JUMP_VELOCITY = 620.0f; // Y units / sec
    static constexpr float GRAVITY = 1500.0f;      // Y units / sec^2
    static constexpr float COYOTE_TIME = 0.10f;    // grace after leaving ground
    static constexpr float JUMP_BUFFER = 0.12f;    // press slightly early, still jumps
    static constexpr float HALF_W = 26.0f;         // collision half-width (X)
    static constexpr float HALF_D = 14.0f;         // collision half-depth (Z)
    static constexpr float CAMERA_YAW = 0.78539816f; // 45 deg isometric
    static constexpr int MAX_COLLIDERS = 16;

    PlayerController();

    // Place the fighter. y is height above the floor (0 = standing on it).
    void reset(float x, float z);
    void set_arena(float min_x, float max_x, float min_z, float max_z);
    // Returns false if the table is full.
    bool add_collider(const AABB& box);
    void clear_colliders() { collider_count_ = 0; }

    // One fixed step. dt is clamped by the caller to <= 1/30.
    // attack_cb is invoked when an attack press is accepted; the game
    // loop answers it through RhythmManager and drives the anim state.
    // Signature: void on_attack(bool is_air, int kind /*0 punch 1 kick 2 throw*/).
    template <typename F> void update(float dt, const PlayerInput& in, F&& on_attack);

    // ---- readouts for the renderer / animation state machine ----
    float x() const { return pos_x_; }
    float z() const { return pos_z_; }
    float y() const { return pos_y_; }          // height above floor
    float height01() const;                     // 0 grounded .. 1 apex
    int facing() const { return facing_; }      // -1 left, +1 right
    State state() const { return state_; }
    bool is_airborne() const { return pos_y_ > 0.0f || state_ == State::JUMPING || state_ == State::FALLING; }
    bool dodge_iframes() const { return state_ == State::DODGING; }
    float attack_timer() const { return attack_timer_; }
    int attack_kind() const { return attack_kind_; }
    void set_hurt(float seconds);               // knockback / hurt state
    void land();                                // forced landing (arena reset)

private:
    void move_axis(float dx, float dz);
    bool overlaps(float x, float z) const;

    float pos_x_, pos_z_, pos_y_;   // pos_y_ = simulated height
    float vel_y_;                   // vertical velocity (Y axis)
    float vel_x_, vel_z_;           // ground-plane velocity (X/Z)
    int facing_;
    State state_;
    float state_timer_;             // time left in the current state
    float attack_timer_;            // time left in the attack anim
    int attack_kind_;               // 0 punch, 1 kick, 2 throw
    float dodge_cd_;
    float coyote_timer_;
    float jump_buffer_timer_;
    bool jump_held_;                // variable jump height: release = cut
    AABB colliders_[MAX_COLLIDERS];
    int collider_count_;
    float arena_min_x_, arena_max_x_, arena_min_z_, arena_max_z_;
};

// Template definition lives here (not in the .cpp): the caller passes a
// lambda for on_attack, so the definition must be visible at the call site.
template <typename F>
inline void PlayerController::update(float dt, const PlayerInput& in, F&& on_attack) {

    if (dodge_cd_ > 0.0f) dodge_cd_ -= dt;
    if (state_timer_ > 0.0f) state_timer_ -= dt;
    if (attack_timer_ > 0.0f) attack_timer_ -= dt;

    const bool airborne = pos_y_ > 0.0f || state_ == State::JUMPING || state_ == State::FALLING;

    // --- jump buffering + coyote time (forgiving on a handheld) ---
    if (in.jump_pressed) jump_buffer_timer_ = JUMP_BUFFER;
    else if (jump_buffer_timer_ > 0.0f) jump_buffer_timer_ -= dt;
    if (!airborne) coyote_timer_ = COYOTE_TIME;
    else if (coyote_timer_ > 0.0f) coyote_timer_ -= dt;

    // --- state transitions ---
    if (state_ == State::HURT && state_timer_ <= 0.0f) state_ = State::GROUNDED;
    if (state_ == State::DODGING && state_timer_ <= 0.0f) state_ = State::GROUNDED;
    if (state_ == State::ATTACKING && attack_timer_ <= 0.0f) state_ = State::GROUNDED;
    if (state_ == State::AIR_ATTACK && pos_y_ <= 0.0f) { land(); }

    const bool busy = state_ == State::ATTACKING || state_ == State::AIR_ATTACK ||
                      state_ == State::DODGING || state_ == State::HURT;

    // --- dodge (ground only, i-frames, fixed distance) ---
    if (in.dodge_pressed && !busy && !airborne && dodge_cd_ <= 0.0f) {
        state_ = State::DODGING;
        state_timer_ = DODGE_TIME;
        dodge_cd_ = DODGE_COOLDOWN;
        vel_x_ = facing_ * DODGE_SPEED;
        vel_z_ = 0.0f;
    }

    // --- jump (variable height: release early = short hop) ---
    if (jump_buffer_timer_ > 0.0f && coyote_timer_ > 0.0f && !busy) {
        vel_y_ = JUMP_VELOCITY;
        pos_y_ = 0.01f;
        state_ = State::JUMPING;
        jump_buffer_timer_ = 0.0f;
        coyote_timer_ = 0.0f;
        jump_held_ = true;
    }
    if (!in.jump_pressed && jump_held_ && vel_y_ > 0.0f) {
        vel_y_ *= 0.5f; // jump cut
        jump_held_ = false;
    }

    // --- attacks: ground combo starter, or air attack ---
    const bool want_attack = in.punch_pressed || in.kick_pressed || in.throw_pressed;
    if (want_attack && !busy) {
        attack_kind_ = in.kick_pressed ? 1 : (in.throw_pressed ? 2 : 0);
        if (airborne) {
            state_ = State::AIR_ATTACK;
            attack_timer_ = 0.32f;
            if (attack_kind_ == 1) vel_y_ = -520.0f; // dive kick: slam down
            on_attack(true, attack_kind_);
        } else {
            state_ = State::ATTACKING;
            attack_timer_ = 0.22f;
            on_attack(false, attack_kind_);
        }
    }

    // --- camera-relative ground movement (isometric: 45 deg yaw) ---
    float mx = 0.0f, mz = 0.0f;
    if (!busy) {
        // Rotate the stick vector by CAMERA_YAW so "up" walks up-screen.
        const float c = 0.70710678f, s = 0.70710678f; // cos/sin(45 deg)
        mx = in.move_x * c - in.move_z * s;
        mz = in.move_x * s + in.move_z * c;
        const float len = std::sqrt(mx * mx + mz * mz);
        if (len > 1.0f) { mx /= len; mz /= len; }
        if (mx > 0.1f) facing_ = 1;
        else if (mx < -0.1f) facing_ = -1;
    }
    const float speed = (state_ == State::DODGING) ? DODGE_SPEED : WALK_SPEED;
    // Air control is weaker than ground control (70%).
    const float control = airborne ? 0.7f : 1.0f;
    vel_x_ = (state_ == State::DODGING) ? vel_x_ : mx * speed * control;
    vel_z_ = (state_ == State::DODGING) ? 0.0f : mz * speed * control;
    move_axis(vel_x_ * dt, vel_z_ * dt);

    // --- simulated Y: gravity + landing ---
    if (airborne || pos_y_ > 0.0f) {
        vel_y_ -= GRAVITY * dt;
        pos_y_ += vel_y_ * dt;
        if (state_ == State::JUMPING && vel_y_ <= 0.0f) state_ = State::FALLING;
        if (pos_y_ <= 0.0f) {
            const bool was_air_attack = state_ == State::AIR_ATTACK;
            land();
            if (was_air_attack) attack_timer_ = 0.12f; // landing recovery
        }
    }
}

// The game loop passes a lambda for on_attack, so the template is
// instantiated in main.cpp. (No .cpp-side instantiation needed.)

} // namespace sleeze
