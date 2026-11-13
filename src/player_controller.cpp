// SLEEZE DISCO v2 — PlayerController implementation.
// Fixed-step, zero-alloc. All temporaries are members or stack values.
#include "player_controller.hpp"
#include <cmath>

namespace sleeze {

PlayerController::PlayerController()
    : pos_x_(300.0f), pos_z_(0.0f), pos_y_(0.0f), vel_y_(0.0f),
      vel_x_(0.0f), vel_z_(0.0f), facing_(1), state_(State::GROUNDED),
      state_timer_(0.0f), attack_timer_(0.0f), attack_kind_(0),
      dodge_cd_(0.0f), coyote_timer_(0.0f), jump_buffer_timer_(0.0f),
      jump_held_(false), collider_count_(0),
      arena_min_x_(60.0f), arena_max_x_(900.0f),
      arena_min_z_(-60.0f), arena_max_z_(60.0f) {}

void PlayerController::reset(float x, float z) {
    pos_x_ = x; pos_z_ = z; pos_y_ = 0.0f;
    vel_x_ = vel_z_ = vel_y_ = 0.0f;
    facing_ = 1; state_ = State::GROUNDED;
    state_timer_ = attack_timer_ = dodge_cd_ = 0.0f;
    coyote_timer_ = jump_buffer_timer_ = 0.0f;
}

void PlayerController::set_arena(float min_x, float max_x, float min_z, float max_z) {
    arena_min_x_ = min_x; arena_max_x_ = max_x;
    arena_min_z_ = min_z; arena_max_z_ = max_z;
}

bool PlayerController::add_collider(const AABB& box) {
    if (collider_count_ >= MAX_COLLIDERS) return false;
    colliders_[collider_count_++] = box;
    return true;
}

float PlayerController::height01() const {
    // Apex of a full jump: v^2 / (2g) = 620^2 / 3000 ~= 128 units.
    const float apex = (JUMP_VELOCITY * JUMP_VELOCITY) / (2.0f * GRAVITY);
    const float h = pos_y_ / apex;
    return h < 0.0f ? 0.0f : (h > 1.0f ? 1.0f : h);
}

bool PlayerController::overlaps(float x, float z) const {
    for (int i = 0; i < collider_count_; ++i) {
        const AABB& b = colliders_[i];
        if (x + HALF_W > b.min_x && x - HALF_W < b.max_x &&
            z + HALF_D > b.min_z && z - HALF_D < b.max_z) return true;
    }
    return false;
}

void PlayerController::move_axis(float dx, float dz) {
    // X axis, then Z axis: sliding along walls falls out for free.
    float nx = pos_x_ + dx;
    if (nx < arena_min_x_) nx = arena_min_x_;
    if (nx > arena_max_x_) nx = arena_max_x_;
    if (!overlaps(nx, pos_z_)) pos_x_ = nx;
    float nz = pos_z_ + dz;
    if (nz < arena_min_z_) nz = arena_min_z_;
    if (nz > arena_max_z_) nz = arena_max_z_;
    if (!overlaps(pos_x_, nz)) pos_z_ = nz;
}

void PlayerController::set_hurt(float seconds) {
    if (state_ == State::DODGING) return; // i-frames: no hurt
    state_ = State::HURT;
    state_timer_ = seconds;
}

void PlayerController::land() {
    pos_y_ = 0.0f; vel_y_ = 0.0f;
    if (state_ == State::JUMPING || state_ == State::FALLING || state_ == State::AIR_ATTACK)
        state_ = State::GROUNDED;
}

} // namespace sleeze
