/* SLEEZE DISCO - Beat Kune Do (PS Vita homebrew)
 *
 * Original rhythm beat-em-up INSPIRED BY Dead as Disco (Brain Jar Games,
 * Unreal Engine 5, PC Early Access May 5 2026). It is NOT a port and NOT
 * a copy: Dead as Disco has no source release, no Vita version, and its
 * art / music / characters are copyrighted. This is a from-scratch
 * Vita-native 2D brawler that recreates the same core loop on hardware
 * the Vita can actually run:
 *   - Beat Kune Do: hits land on the beat. Perfect +-60ms = +50% dmg,
 *     Good +-120ms = +10%, off-beat hits are NOT penalised (mashing
 *     still looks like a fight scene, timing pays on top).
 *   - Dodge / counter prompts light up in the perfect window.
 *   - Takedown meter -> finisher when the marker shows.
 *   - Beat the Idol to unlock a skill-tree ability.
 *   - Infinite Disco endless score attack + My Music (WAVs in
 *     ux0:data/SLEEZEDISCO/music/, BPM set per track).
 *   - Story: Neon Alley (100 BPM) -> Dive Bar (120 BPM) -> Idol VEX (140 BPM).
 * Protagonist is original: Jay Sleeze, fallen singer back for one night.
 * All art is drawn in code, all music is synthesized (see audio.c).
 * No licensed music, no ripped assets.
 *
 * Build: VitaSDK (arm-vita-eabi), CMake. Produces SLEEZEDISCO.vpk.
 * Controls: Square punch, Triangle kick, Circle drumstick throw,
 *   Cross dodge, L counter/parry, R+Square Takedown, Start pause.
 * Requires a hacked Vita (HENkaku / h-encore). Install the .vpk in VitaShell.
 * 960x544, software framebuffer, ~60fps, 444MHz.
 */
#include <psp2/display.h>
#include <psp2/ctrl.h>
#include <psp2/power.h>
#include <psp2/kernel/processmgr.h>
#include <psp2/kernel/threadmgr.h>
#include <psp2/io/fcntl.h>
#include <psp2/io/stat.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include "audio.h"

#define W 960
#define H 544
#define FB_SIZE (W * H)

/* ---------- framebuffer (double buffered, ABGR8888) ---------- */
static uint32_t fb[2][FB_SIZE];
static int cur_fb = 0;
static uint32_t *g_px = NULL;

#define C_RGB(r, g, b) ((uint32_t)(0xFF000000u | ((b) << 16) | ((g) << 8) | (r)))
#define COL_BLACK   C_RGB(8, 8, 12)
#define COL_BG      C_RGB(14, 10, 22)
#define COL_WHITE   C_RGB(235, 235, 235)
#define COL_GREY    C_RGB(140, 140, 150)
#define COL_RED     C_RGB(230, 30, 50)
#define COL_RED_DK  C_RGB(120, 10, 25)
#define COL_GOLD    C_RGB(255, 200, 60)
#define COL_CYAN    C_RGB(60, 220, 255)
#define COL_PURPLE  C_RGB(150, 80, 255)
#define COL_GREEN   C_RGB(80, 230, 120)
#define COL_PINK    C_RGB(255, 80, 180)
#define COL_DARK    C_RGB(28, 20, 38)

static void flip(void) {
    SceDisplayFrameBuf f;
    memset(&f, 0, sizeof(f));
    f.size = sizeof(f);
    f.base = fb[cur_fb];
    f.pitch = W;
    f.pixelformat = SCE_DISPLAY_PIXELFORMAT_A8B8G8R8;
    f.width = W;
    f.height = H;
    sceDisplaySetFrameBuf(&f, SCE_DISPLAY_SETBUF_NEXTFRAME);
    sceDisplayWaitVblankStart();
    cur_fb ^= 1;
    g_px = fb[cur_fb];
}

static void clear_screen(uint32_t c) {
    for (int i = 0; i < FB_SIZE; i++) g_px[i] = c;
}

static void fill_rect(int x, int y, int w, int h, uint32_t c) {
    if (x < 0) { w += x; x = 0; }
    if (y < 0) { h += y; y = 0; }
    if (x + w > W) w = W - x;
    if (y + h > H) h = H - y;
    if (w <= 0 || h <= 0) return;
    for (int j = 0; j < h; j++) {
        uint32_t *row = g_px + (y + j) * W + x;
        for (int i = 0; i < w; i++) row[i] = c;
    }
}

static void draw_rect_outline(int x, int y, int w, int h, uint32_t c) {
    fill_rect(x, y, w, 2, c);
    fill_rect(x, y + h - 2, w, 2, c);
    fill_rect(x, y, 2, h, c);
    fill_rect(x + w - 2, y, 2, h, c);
}

static void fill_circle(int cx, int cy, int r, uint32_t c) {
    for (int y = -r; y <= r; y++) {
        int dx = (int)sqrtf((float)(r * r - y * y));
        int yy = cy + y;
        if (yy < 0 || yy >= H) continue;
        int x0 = cx - dx; if (x0 < 0) x0 = 0;
        int x1 = cx + dx; if (x1 >= W) x1 = W - 1;
        for (int x = x0; x <= x1; x++) g_px[yy * W + x] = c;
    }
}

/* ---------- tiny 3x5 font, scaled. Rows are 3-bit values, bit2 = left. ---------- */
static void glyph_rows(char ch, uint8_t r[5]) {
    /* default: blank */
    r[0]=0; r[1]=0; r[2]=0; r[3]=0; r[4]=0;
    switch (ch) {
    case 'A': r[0]=2; r[1]=5; r[2]=7; r[3]=5; r[4]=5; break;
    case 'B': r[0]=6; r[1]=5; r[2]=6; r[3]=5; r[4]=6; break;
    case 'C': r[0]=3; r[1]=4; r[2]=4; r[3]=4; r[4]=3; break;
    case 'D': r[0]=6; r[1]=5; r[2]=5; r[3]=5; r[4]=6; break;
    case 'E': r[0]=7; r[1]=4; r[2]=6; r[3]=4; r[4]=7; break;
    case 'F': r[0]=7; r[1]=4; r[2]=6; r[3]=4; r[4]=4; break;
    case 'G': r[0]=3; r[1]=4; r[2]=5; r[3]=5; r[4]=3; break;
    case 'H': r[0]=5; r[1]=5; r[2]=7; r[3]=5; r[4]=5; break;
    case 'I': r[0]=7; r[1]=2; r[2]=2; r[3]=2; r[4]=7; break;
    case 'J': r[0]=1; r[1]=1; r[2]=1; r[3]=5; r[4]=2; break;
    case 'K': r[0]=5; r[1]=5; r[2]=6; r[3]=5; r[4]=5; break;
    case 'L': r[0]=4; r[1]=4; r[2]=4; r[3]=4; r[4]=7; break;
    case 'M': r[0]=5; r[1]=7; r[2]=7; r[3]=5; r[4]=5; break;
    case 'N': r[0]=5; r[1]=7; r[2]=7; r[3]=7; r[4]=5; break;
    case 'O': r[0]=2; r[1]=5; r[2]=5; r[3]=5; r[4]=2; break;
    case 'P': r[0]=6; r[1]=5; r[2]=6; r[3]=4; r[4]=4; break;
    case 'Q': r[0]=2; r[1]=5; r[2]=5; r[3]=6; r[4]=3; break;
    case 'R': r[0]=6; r[1]=5; r[2]=6; r[3]=5; r[4]=5; break;
    case 'S': r[0]=3; r[1]=4; r[2]=2; r[3]=1; r[4]=6; break;
    case 'T': r[0]=7; r[1]=2; r[2]=2; r[3]=2; r[4]=2; break;
    case 'U': r[0]=5; r[1]=5; r[2]=5; r[3]=5; r[4]=7; break;
    case 'V': r[0]=5; r[1]=5; r[2]=5; r[3]=5; r[4]=2; break;
    case 'W': r[0]=5; r[1]=5; r[2]=7; r[3]=7; r[4]=5; break;
    case 'X': r[0]=5; r[1]=5; r[2]=2; r[3]=5; r[4]=5; break;
    case 'Y': r[0]=5; r[1]=5; r[2]=2; r[3]=2; r[4]=2; break;
    case 'Z': r[0]=7; r[1]=1; r[2]=2; r[3]=4; r[4]=7; break;
    case '0': r[0]=2; r[1]=5; r[2]=5; r[3]=5; r[4]=2; break;
    case '1': r[0]=2; r[1]=2; r[2]=2; r[3]=2; r[4]=2; break;
    case '2': r[0]=6; r[1]=1; r[2]=2; r[3]=4; r[4]=7; break;
    case '3': r[0]=6; r[1]=1; r[2]=2; r[3]=1; r[4]=6; break;
    case '4': r[0]=5; r[1]=5; r[2]=7; r[3]=1; r[4]=1; break;
    case '5': r[0]=7; r[1]=4; r[2]=6; r[3]=1; r[4]=6; break;
    case '6': r[0]=3; r[1]=4; r[2]=6; r[3]=5; r[4]=2; break;
    case '7': r[0]=7; r[1]=1; r[2]=2; r[3]=2; r[4]=2; break;
    case '8': r[0]=2; r[1]=5; r[2]=2; r[3]=5; r[4]=2; break;
    case '9': r[0]=2; r[1]=5; r[2]=3; r[3]=1; r[4]=6; break;
    case ' ': break;
    case '.': r[4]=2; break;
    case ',': r[3]=2; r[4]=4; break;
    case '!': r[0]=2; r[1]=2; r[2]=2; r[3]=0; r[4]=2; break;
    case '?': r[0]=6; r[1]=1; r[2]=2; r[3]=0; r[4]=2; break;
    case ':': r[1]=2; r[3]=2; break;
    case '-': r[2]=7; break;
    case '+': r[1]=2; r[2]=7; r[3]=2; break;
    case '/': r[0]=1; r[1]=1; r[2]=2; r[3]=4; r[4]=4; break;
    case '%': r[0]=5; r[1]=1; r[2]=2; r[3]=4; r[4]=5; break;
    case '(': r[0]=1; r[1]=2; r[2]=2; r[3]=2; r[4]=1; break;
    case ')': r[0]=4; r[1]=2; r[2]=2; r[3]=2; r[4]=4; break;
    case '\'': r[0]=2; r[1]=2; break;
    case '*': r[0]=5; r[1]=2; r[2]=7; r[3]=2; r[4]=5; break;
    case '=': r[1]=7; r[3]=7; break;
    case '<': r[0]=1; r[1]=2; r[2]=4; r[3]=2; r[4]=1; break;
    case '>': r[0]=4; r[1]=2; r[2]=1; r[3]=2; r[4]=4; break;
    default: break;
    }
}

static void draw_char(int x, int y, int scale, char ch, uint32_t c) {
    if (ch >= 'a' && ch <= 'z') ch = (char)(ch - 'a' + 'A');
    uint8_t r[5];
    glyph_rows(ch, r);
    for (int row = 0; row < 5; row++)
        for (int col = 0; col < 3; col++)
            if (r[row] & (1 << (2 - col)))
                fill_rect(x + col * scale, y + row * scale, scale, scale, c);
}

static int text_w(const char *s, int scale) { return (int)strlen(s) * 4 * scale; }

static void draw_text(int x, int y, int scale, const char *s, uint32_t c) {
    for (int i = 0; s[i]; i++) draw_char(x + i * 4 * scale, y, scale, s[i], c);
}

static void draw_text_center(int y, int scale, const char *s, uint32_t c) {
    draw_text((W - text_w(s, scale)) / 2, y, scale, s, c);
}

/* ---------- timing / input ---------- */
static uint64_t now_us(void) { return sceKernelGetProcessTimeWide(); }

static SceCtrlData pad, prev_pad;
static int pressed(unsigned int b) { return (pad.buttons & b) && !(prev_pad.buttons & b); }

/* ---------- save ---------- */
#define SAVE_PATH "ux0:data/SLEEZEDISCO/save.bin"
typedef struct { int hi_score; int fans; int vex_beaten; int perfect_strikes; } SaveData;
static SaveData g_save;
static void save_load(void) {
    memset(&g_save, 0, sizeof(g_save));
    sceIoMkdir("ux0:data/SLEEZEDISCO", 0777);
    SceUID f = sceIoOpen(SAVE_PATH, SCE_O_RDONLY, 0777);
    if (f >= 0) { sceIoRead(f, &g_save, sizeof(g_save)); sceIoClose(f); }
}
static void save_store(void) {
    SceUID f = sceIoOpen(SAVE_PATH, SCE_O_WRONLY | SCE_O_CREAT | SCE_O_TRUNC, 0777);
    if (f >= 0) { sceIoWrite(f, &g_save, sizeof(g_save)); sceIoClose(f); }
}

/* ---------- songs / beat engine ---------- */
typedef struct { const char *name; int bpm; int root; int style; int bars; } SongDef;
static const SongDef SONGS[3] = {
    {"NEON ALLEY", 100, 45, 0, 16},
    {"DIVE BAR",   120, 41, 1, 16},
    {"VEX - IDOL", 140, 43, 2, 16},
};
static Track *g_track = NULL;
static uint64_t g_song_start_us = 0;
static int g_bpm = 120;
static double beat_len(void) { return 60.0 / (double)g_bpm; }

/* ms to nearest beat; negative = just before, positive = just after. */
static double ms_to_beat(void) {
    double t = (double)(now_us() - g_song_start_us) / 1000.0;
    double bl = beat_len() * 1000.0;
    double ph = fmod(t, bl);
    if (ph > bl / 2.0) return ph - bl;
    return ph;
}
static double beat_phase01(void) {
    double t = (double)(now_us() - g_song_start_us) / 1000.0;
    double bl = beat_len() * 1000.0;
    return fmod(t, bl) / bl;
}
/* 0=miss/off, 1=good, 2=perfect. Off-beat is NOT penalised, per the real game. */
static int judge_hit(void) {
    double m = ms_to_beat(); if (m < 0) m = -m;
    if (m <= 60.0) return 2;
    if (m <= 120.0) return 1;
    return 0;
}

/* ---------- game state ---------- */
enum { ST_TITLE, ST_MODES, ST_HOWTO, ST_FIGHT, ST_PAUSE, ST_WIN, ST_LOSE, ST_RESULTS };
static int g_state = ST_TITLE;
static int g_menu = 0;          /* menu cursor */
static int g_mode = 0;          /* 0 story, 1 infinite, 2 my music */
static int g_chapter = 0;       /* 0..2 story */

typedef struct {
    int x, y, hp, max_hp, type; /* 0 Stan, 1 Charger, 2 Bruiser, 3 VEX boss */
    int state;                  /* 0 walk, 1 windup, 2 attack, 3 stunned, 4 dying */
    uint64_t state_t;
    int flash;                  /* hit flash frames */
    int perfects_taken;         /* Bruiser stun counter */
    int atk_cd;
} Enemy;

#define MAX_ENEMIES 6
static Enemy g_enemies[MAX_ENEMIES];
static int g_wave = 1, g_kills = 0, g_to_spawn = 0;
static uint64_t g_spawn_t = 0;

typedef struct {
    int x, y, hp, max_hp;
    int facing;                 /* 1 right, -1 left */
    uint64_t dodge_until, dodge_cd, atk_cd, counter_until;
    int atk_anim;               /* frames left of swing anim */
    int atk_kind;               /* 0 punch, 1 kick, 2 throw */
    int iframes_until_ms;       /* stored as us deadline */
    uint64_t iframes_us;
    int meter;                  /* takedown 0..100 */
    int dead;
} Player;
static Player g_pl;

static int g_score = 0, g_combo = 0, g_max_combo = 0;
static int g_perfect = 0, g_good = 0, g_off = 0;
static int g_shake = 0;
static char g_judge[16] = "";
static uint64_t g_judge_t = 0;
static int g_float_dmg = 0, g_float_x = 0, g_float_y = 0;
static uint64_t g_float_t = 0;
static int g_boss_phase = 1;
static int g_takedown_flash = 0;

/* projectiles: drumsticks (player) + beat-wave orbs (boss) */
typedef struct { int x, y, vx, alive, friendly, dmg; } Proj;
#define MAX_PROJ 16
static Proj g_proj[MAX_PROJ];

static void clear_enemies(void) {
    memset(g_enemies, 0, sizeof(g_enemies));
    for (int i = 0; i < MAX_ENEMIES; i++) g_enemies[i].hp = -1;
    memset(g_proj, 0, sizeof(g_proj));
}

static void spawn_enemy(int type) {
    for (int i = 0; i < MAX_ENEMIES; i++) {
        if (g_enemies[i].hp > 0) continue;
        Enemy *e = &g_enemies[i];
        memset(e, 0, sizeof(*e));
        e->type = type;
        e->x = 880 + (rand() % 60);
        e->y = 380;
        e->state = 0;
        e->state_t = now_us();
        if (type == 0) { e->hp = e->max_hp = 24; }
        if (type == 1) { e->hp = e->max_hp = 20; }
        if (type == 2) { e->hp = e->max_hp = 60; }
        if (type == 3) { e->hp = e->max_hp = 300; e->x = 720; }
        return;
    }
}

static void start_fight(int mode, int chapter, int bpm) {
    g_mode = mode; g_chapter = chapter; g_bpm = bpm;
    memset(&g_pl, 0, sizeof(g_pl));
    g_pl.x = 300; g_pl.y = 380; g_pl.hp = g_pl.max_hp = 100; g_pl.facing = 1;
    g_score = 0; g_combo = 0; g_max_combo = 0;
    g_perfect = 0; g_good = 0; g_off = 0;
    g_wave = 1; g_kills = 0; g_boss_phase = 1; g_takedown_flash = 0;
    g_judge[0] = 0;
    clear_enemies();
    if (mode == 0 && chapter == 2) {
        spawn_enemy(3); /* VEX */
        g_to_spawn = 0;
    } else if (mode == 0) {
        g_to_spawn = 3 + chapter * 2;
        g_spawn_t = now_us() + 800000;
    } else {
        g_to_spawn = 4;
        g_spawn_t = now_us() + 800000;
    }
    /* (re)build the synth track for this tempo */
    if (g_track) { audio_stop(); audio_free_track(g_track); g_track = NULL; }
    const SongDef *sd = &SONGS[chapter < 3 ? chapter : 1];
    int style = (mode == 0 && chapter == 2) ? 2 : (g_bpm >= 130 ? 2 : (g_bpm >= 115 ? 1 : 0));
    int root = (mode == 0) ? sd->root : 43;
    char tname[48];
    snprintf(tname, sizeof(tname), "%s %d BPM", (mode == 0) ? sd->name : "MY MUSIC", g_bpm);
    g_track = audio_gen_track(tname, g_bpm, 16, root, style);
    if (g_track) audio_start(g_track);
    g_song_start_us = now_us() + 400000; /* 400ms count-in */
    g_state = ST_FIGHT;
}

static void end_fight(int won) {
    audio_stop();
    if (g_score > g_save.hi_score) g_save.hi_score = g_score;
    g_save.fans += g_score / 100;
    if (won && g_mode == 0 && g_chapter == 2) {
        g_save.vex_beaten = 1;
        g_save.perfect_strikes = 1;
    }
    save_store();
    g_state = won ? ST_WIN : ST_LOSE;
}

/* ---------- combat ---------- */
static void add_judge(int j, int x, int y, int dmg) {
    if (j == 2) { strcpy(g_judge, "PERFECT!"); g_perfect++; }
    else if (j == 1) { strcpy(g_judge, "GOOD"); g_good++; }
    else { strcpy(g_judge, "HIT"); g_off++; }
    g_judge_t = now_us();
    g_float_dmg = dmg; g_float_x = x; g_float_y = y; g_float_t = now_us();
    g_shake = j == 2 ? 6 : 3;
}

static void hurt_enemy(Enemy *e, int base, int j) {
    int dmg = base;
    if (j == 2) dmg = base + base / 2;          /* Perfect +50% */
    else if (j == 1) dmg = base + base / 10;    /* Good +10% */
    if (g_save.perfect_strikes && j == 2) dmg += 2;
    e->hp -= dmg;
    e->flash = 5;
    g_combo++;
    if (g_combo > g_max_combo) g_max_combo = g_combo;
    g_score += dmg * 10 + g_combo * 5;
    g_pl.meter += (j == 2) ? 12 : 7;
    if (g_pl.meter > 100) g_pl.meter = 100;
    if (e->type == 2 && j == 2) {
        e->perfects_taken++;
        if (e->perfects_taken >= 4) { e->state = 3; e->state_t = now_us(); e->perfects_taken = 0; }
    }
    add_judge(j, e->x, e->y - 70, dmg);
    if (e->hp <= 0) {
        e->hp = -1; e->state = 4;
        g_kills++;
        g_score += 500;
        g_pl.meter += 10; if (g_pl.meter > 100) g_pl.meter = 100;
        if (e->type == 3) { end_fight(1); return; }
    }
}

static void player_attack(int kind) {
    if (now_us() < g_pl.atk_cd) return;
    if (g_pl.dodge_until > now_us()) return;
    int j = judge_hit();
    g_pl.atk_anim = 10; g_pl.atk_kind = kind;
    g_pl.atk_cd = now_us() + 220000;
    if (kind == 2) {
        /* drumstick throw: ranged */
        for (int i = 0; i < MAX_PROJ; i++) if (!g_proj[i].alive) {
            g_proj[i].alive = 1; g_proj[i].friendly = 1;
            g_proj[i].x = g_pl.x + 40; g_proj[i].y = g_pl.y - 40;
            g_proj[i].vx = 14; g_proj[i].dmg = 6;
            break;
        }
        if (j == 2) g_perfect++; else if (j == 1) g_good++; else g_off++;
        g_pl.meter += 5; if (g_pl.meter > 100) g_pl.meter = 100;
        return;
    }
    int range = (kind == 0) ? 110 : 140;
    int base = (kind == 0) ? 8 : 12;
    int hit_any = 0;
    for (int i = 0; i < MAX_ENEMIES; i++) {
        Enemy *e = &g_enemies[i];
        if (e->hp <= 0) continue;
        int dx = e->x - g_pl.x;
        if (g_pl.facing == 1 ? (dx > -20 && dx < range) : (dx < 20 && dx > -range)) {
            hurt_enemy(e, base, j);
            hit_any = 1;
            if (g_state != ST_FIGHT) return;
        }
    }
    if (!hit_any) { /* whiff on the beat still counts as a swing, no penalty */
        if (j == 2) g_perfect++; else if (j == 1) g_good++; else g_off++;
    }
}

static void player_takedown(void) {
    if (g_pl.meter < 100) return;
    if (now_us() < g_pl.atk_cd) return;
    g_pl.meter = 0;
    g_takedown_flash = 12;
    g_shake = 10;
    strcpy(g_judge, "TAKEDOWN!");
    g_judge_t = now_us();
    for (int i = 0; i < MAX_ENEMIES; i++) {
        Enemy *e = &g_enemies[i];
        if (e->hp <= 0) continue;
        int dx = e->x - g_pl.x; if (dx < 0) dx = -dx;
        if (dx < 260) {
            e->hp -= 40; e->flash = 8;
            g_score += 1000;
            if (e->hp <= 0) { e->hp = -1; g_kills++; if (e->type == 3) { end_fight(1); return; } }
        }
    }
}

static void hurt_player(int dmg) {
    if (now_us() < g_pl.iframes_us) return;
    if (now_us() < g_pl.dodge_until) return;
    g_pl.hp -= dmg;
    g_combo = 0;
    g_shake = 6;
    strcpy(g_judge, "OUCH");
    g_judge_t = now_us();
    g_pl.iframes_us = now_us() + 600000;
    if (g_pl.hp <= 0) { g_pl.hp = 0; g_pl.dead = 1; end_fight(0); }
}

/* ---------- enemy AI: walk in, telegraph on the beat, strike ---------- */
static void update_enemies(void) {
    uint64_t now = now_us();
    /* spawner: one enemy per 2 beats while the queue lasts */
    if (g_to_spawn > 0 && now >= g_spawn_t) {
        int r = rand() % 10;
        int type = 0;
        if (g_mode == 1 && g_wave >= 3 && r < 2) type = 2;
        else if (r < 2) type = 1;
        else if (g_wave >= 2 && r < 3) type = 2;
        spawn_enemy(type);
        g_to_spawn--;
        g_spawn_t = now + (uint64_t)(beat_len() * 2.0 * 1000000.0);
    }
    for (int i = 0; i < MAX_ENEMIES; i++) {
        Enemy *e = &g_enemies[i];
        if (e->hp <= 0) continue;
        if (e->flash > 0) e->flash--;
        int dist = e->x - g_pl.x;
        if (e->state == 3) { /* stunned */
            if (now - e->state_t > 1500000) { e->state = 0; e->state_t = now; }
            continue;
        }
        if (e->type == 3) {
            /* VEX: phases, Beat Wave orbs + Spotlight Spin */
            if (e->hp < 200 && g_boss_phase == 1) { g_boss_phase = 2; strcpy(g_judge, "VEX: PHASE 2"); g_judge_t = now; }
            if (e->hp < 100 && g_boss_phase == 2) { g_boss_phase = 3; strcpy(g_judge, "VEX: FINAL"); g_judge_t = now; }
            if (e->state == 0) {
                if (dist > 180) e->x -= 2;
                else if (dist < 120) e->x += 1;
                /* telegraph every ~4 beats */
                double ph = beat_phase01();
                if (ph < 0.06 && (rand() % 60) == 0) { e->state = 1; e->state_t = now; }
            } else if (e->state == 1) {
                if (now - e->state_t > 500000) {
                    e->state = 2; e->state_t = now;
                    /* Beat Wave: 3 orbs */
                    for (int k = 0; k < 3; k++)
                        for (int p = 0; p < MAX_PROJ; p++) if (!g_proj[p].alive) {
                            g_proj[p].alive = 1; g_proj[p].friendly = 0;
                            g_proj[p].x = e->x - 20; g_proj[p].y = e->y - 60 + k * 30;
                            g_proj[p].vx = -9 - g_boss_phase; g_proj[p].dmg = 10;
                            break;
                        }
                }
            } else if (e->state == 2) {
                if (now - e->state_t > 400000) { e->state = 0; e->state_t = now; }
            }
            continue;
        }
        if (e->state == 0) {
            int speed = (e->type == 1) ? 3 : 2;
            if (dist > 90) e->x -= speed;
            else if (dist < 50) e->x += 1;
            else {
                /* in range: wind up on the next beat */
                if (beat_phase01() < 0.08) { e->state = 1; e->state_t = now; }
            }
        } else if (e->state == 1) {
            /* windup 500ms: dodge / counter window. Counter prompt lights. */
            if (now - e->state_t > 500000) {
                e->state = 2; e->state_t = now;
                if (e->type == 1) { e->x -= 60; } /* Charger lunges */
                int d = e->x - g_pl.x; if (d < 0) d = -d;
                if (d < 110) hurt_player(e->type == 2 ? 14 : 8);
            }
        } else if (e->state == 2) {
            if (now - e->state_t > 450000) { e->state = 0; e->state_t = now; }
        }
    }
    /* projectiles */
    for (int i = 0; i < MAX_PROJ; i++) {
        Proj *p = &g_proj[i];
        if (!p->alive) continue;
        p->x += p->vx;
        if (p->x < -20 || p->x > W + 20) { p->alive = 0; continue; }
        if (p->friendly) {
            for (int k = 0; k < MAX_ENEMIES; k++) {
                Enemy *e = &g_enemies[k];
                if (e->hp <= 0) continue;
                int dx = p->x - e->x; if (dx < 0) dx = -dx;
                if (dx < 40 && p->y > e->y - 110 && p->y < e->y + 10) {
                    hurt_enemy(e, p->dmg, judge_hit());
                    p->alive = 0;
                    break;
                }
            }
        } else {
            int dx = p->x - g_pl.x; if (dx < 0) dx = -dx;
            if (dx < 36 && p->y > g_pl.y - 100 && p->y < g_pl.y + 10) {
                hurt_player(p->dmg);
                p->alive = 0;
            }
        }
    }
    /* wave clear -> next wave (story + infinite) */
    int alive = 0;
    for (int i = 0; i < MAX_ENEMIES; i++) if (g_enemies[i].hp > 0) alive++;
    if (alive == 0 && g_to_spawn == 0 && g_state == ST_FIGHT) {
        if (g_mode == 1) {
            g_wave++;
            g_to_spawn = 3 + g_wave;
            if (g_pl.hp < g_pl.max_hp) g_pl.hp += 15;
            if (g_pl.hp > g_pl.max_hp) g_pl.hp = g_pl.max_hp;
            g_spawn_t = now + 1000000;
            strcpy(g_judge, "WAVE CLEAR!");
            g_judge_t = now;
        } else if (g_mode == 0 && g_chapter < 2) {
            end_fight(1);
        } else if (g_mode == 2) {
            g_wave++;
            g_to_spawn = 4;
            g_spawn_t = now + 1000000;
        }
    }
}

/* ---------- drawing ---------- */
static void draw_bg(int beat_pulse) {
    clear_screen(COL_BG);
    /* neon skyline, parallax by beat */
    int off = beat_pulse ? 2 : 0;
    for (int i = 0; i < 12; i++) {
        int bx = i * 85 - off * 3;
        int bh = 90 + ((i * 37) % 120);
        fill_rect(bx, 300 - bh, 70, bh, C_RGB(22 + i * 2, 16, 40));
        fill_rect(bx + 8, 300 - bh + 12, 10, 10, (i % 3 == 0) ? COL_CYAN : COL_PURPLE);
        fill_rect(bx + 30, 300 - bh + 30, 10, 10, (i % 4 == 0) ? COL_RED : COL_GOLD);
    }
    /* floor */
    fill_rect(0, 380, W, 164, C_RGB(20, 14, 30));
    for (int i = 0; i < 24; i++)
        fill_rect(i * 42, 380 + ((i % 2) * 40), 40, 2, C_RGB(40, 30, 60));
    /* neon sign */
    draw_text(700, 60, 3, "ENCORE", COL_PINK);
    draw_text(700, 84, 2, "DIVE BAR", COL_CYAN);
    /* grit speckle (B&W photocopy feel) */
    for (int i = 0; i < 40; i++) {
        int x = (i * 173) % W, y = (i * 97) % 300;
        fill_rect(x, y, 2, 2, C_RGB(60, 60, 70));
    }
}

static void draw_fighter(int x, int y, int facing, uint32_t body, uint32_t head,
                          int anim, int kind, int flash) {
    int shx = (g_shake > 0) ? ((rand() % 7) - 3) : 0;
    x += shx;
    uint32_t b = flash > 0 ? COL_WHITE : body;
    /* legs */
    fill_rect(x - 14, y - 46, 10, 46, b);
    fill_rect(x + 4, y - 46, 10, 46, b);
    /* torso */
    fill_rect(x - 20, y - 96, 40, 54, b);
    /* head + mic / hat */
    fill_circle(x, y - 112, 16, flash > 0 ? COL_WHITE : head);
    fill_rect(x - 18, y - 126, 36, 6, COL_RED);
    /* arm swing */
    int reach = 0;
    if (anim > 0) reach = (kind == 1) ? 55 : 42;
    if (facing == 1) fill_rect(x + 14, y - 88, 26 + reach, 10, b);
    else fill_rect(x - 40 - reach, y - 88, 26 + reach, 10, b);
}

static void draw_enemy(Enemy *e) {
    if (e->hp <= 0) return;
    uint32_t body = COL_GREY, head = COL_GREY;
    if (e->type == 0) { body = C_RGB(90, 90, 110); head = C_RGB(180, 180, 190); }
    if (e->type == 1) { body = COL_RED; head = C_RGB(255, 180, 120); }
    if (e->type == 2) { body = C_RGB(60, 40, 90); head = C_RGB(150, 120, 200); }
    if (e->type == 3) { body = COL_PURPLE; head = COL_GOLD; }
    int h = (e->type == 2) ? 130 : (e->type == 3) ? 160 : 100;
    int x = e->x, y = e->y;
    if (e->state == 1) { /* windup: red flash telegraph */
        if ((now_us() / 100000) % 2 == 0) fill_rect(x - 34, y - h - 26, 68, 8, COL_RED);
        draw_text(x - 28, y - h - 46, 2, "DODGE!", COL_RED);
    }
    if (e->state == 3) draw_text(x - 24, y - h - 46, 2, "STUNNED", COL_GOLD);
    uint32_t b = e->flash > 0 ? COL_WHITE : body;
    fill_rect(x - 18, y - 50, 12, 50, b);
    fill_rect(x + 6, y - 50, 12, 50, b);
    fill_rect(x - 24, y - h, 48, h - 50, b);
    fill_circle(x, y - h - 12, (e->type == 3) ? 22 : 16, e->flash > 0 ? COL_WHITE : head);
    if (e->type == 3) { fill_rect(x - 24, y - h - 40, 48, 8, COL_GOLD); } /* crown */
    if (e->type == 1) { fill_rect(x - 30, y - h - 8, 12, 6, COL_RED); }   /* mohawk */
    /* hp bar */
    int bw = (e->type == 3) ? 200 : 60;
    int bx = (e->type == 3) ? (W - bw) / 2 : x - bw / 2;
    int by = (e->type == 3) ? 30 : y - h - 64;
    fill_rect(bx - 2, by - 2, bw + 4, 10, COL_BLACK);
    fill_rect(bx, by, bw * e->hp / e->max_hp, 6, (e->type == 3) ? COL_PURPLE : COL_RED);
    if (e->type == 3) draw_text_center(12, 2, "VEX - IDOL OF THE NIGHT", COL_GOLD);
}

static void draw_hud(void) {
    /* top bar */
    fill_rect(0, 0, W, 52, C_RGB(10, 8, 16));
    char buf[64];
    snprintf(buf, sizeof(buf), "HP %d", g_pl.hp);
    draw_text(16, 16, 3, buf, COL_WHITE);
    fill_rect(120, 18, 200, 14, COL_BLACK);
    fill_rect(120, 18, 200 * g_pl.hp / g_pl.max_hp, 14, g_pl.hp > 30 ? COL_GREEN : COL_RED);
    snprintf(buf, sizeof(buf), "SCORE %d", g_score);
    draw_text(360, 16, 3, buf, COL_GOLD);
    snprintf(buf, sizeof(buf), "COMBO X%d", g_combo);
    draw_text(600, 16, 3, buf, g_combo >= 10 ? COL_GOLD : COL_WHITE);
    snprintf(buf, sizeof(buf), "FANS %d", g_save.fans + g_score / 100);
    draw_text(800, 16, 3, buf, COL_PINK);
    /* takedown meter */
    draw_text(16, 60, 2, "TAKEDOWN", COL_WHITE);
    fill_rect(110, 60, 200, 12, COL_BLACK);
    fill_rect(110, 60, 200 * g_pl.meter / 100, 12, g_pl.meter >= 100 ? COL_GOLD : COL_CYAN);
    if (g_pl.meter >= 100) draw_text(320, 60, 2, "READY! R+SQUARE", COL_GOLD);
    /* beat pulse bar at bottom */
    double ph = beat_phase01();
    int pulse_w = (int)(ph * W);
    fill_rect(0, 520, W, 24, C_RGB(20, 16, 30));
    fill_rect(0, 520, pulse_w, 24, C_RGB(40, 30, 70));
    /* beat marker: gold in the perfect window */
    double m = ms_to_beat(); if (m < 0) m = -m;
    uint32_t beat_col = (m <= 60.0) ? COL_GOLD : (m <= 120.0 ? COL_CYAN : COL_GREY);
    fill_rect(W / 2 - 30, 516, 60, 32, beat_col);
    draw_text_center(500, 1, "BEAT", COL_BLACK);
    /* judgement */
    if (g_judge[0] && now_us() - g_judge_t < 900000) {
        uint32_t jc = (strcmp(g_judge, "PERFECT!") == 0) ? COL_GOLD :
                      (strcmp(g_judge, "TAKEDOWN!") == 0) ? COL_RED : COL_WHITE;
        draw_text_center(120, 4, g_judge, jc);
    }
    if (g_float_dmg > 0 && now_us() - g_float_t < 700000) {
        char d[16]; snprintf(d, sizeof(d), "%d", g_float_dmg);
        draw_text(g_float_x, g_float_y - 90, 3, d, COL_GOLD);
    }
    /* wave / chapter label */
    char w[64];
    if (g_mode == 0) snprintf(w, sizeof(w), "%s  -  WAVE %d", SONGS[g_chapter].name, g_wave);
    else if (g_mode == 1) snprintf(w, sizeof(w), "INFINITE DISCO  -  WAVE %d", g_wave);
    else snprintf(w, sizeof(w), "MY MUSIC  -  %d BPM  -  WAVE %d", g_bpm, g_wave);
    draw_text(16, 90, 2, w, COL_GREY);
    if (g_takedown_flash > 0) { fill_rect(0, 0, W, 8, COL_RED); fill_rect(0, H - 8, W, 8, COL_RED); }
}

static void draw_fight(void) {
    double m = ms_to_beat(); if (m < 0) m = -m;
    draw_bg(m <= 60.0);
    /* projectiles */
    for (int i = 0; i < MAX_PROJ; i++) {
        Proj *p = &g_proj[i];
        if (!p->alive) continue;
        if (p->friendly) { fill_rect(p->x - 12, p->y - 4, 24, 8, COL_GOLD); }
        else fill_circle(p->x, p->y, 10, COL_PURPLE);
    }
    /* player */
    draw_fighter(g_pl.x, g_pl.y, g_pl.facing, C_RGB(30, 30, 40), C_RGB(235, 210, 180),
                 g_pl.atk_anim, g_pl.atk_kind, 0);
    /* counter prompt: L lights up while an enemy is winding up */
    int winding = 0;
    for (int i = 0; i < MAX_ENEMIES; i++) if (g_enemies[i].hp > 0 && g_enemies[i].state == 1) winding = 1;
    if (winding) draw_text(g_pl.x - 30, g_pl.y - 170, 2, "[L] COUNTER!", COL_CYAN);
    for (int i = 0; i < MAX_ENEMIES; i++) draw_enemy(&g_enemies[i]);
    draw_hud();
    if (g_shake > 0) g_shake--;
    if (g_takedown_flash > 0) g_takedown_flash--;
    if (g_pl.atk_anim > 0) g_pl.atk_anim--;
}

/* ---------- menus ---------- */
static void draw_title(void) {
    draw_bg(1);
    draw_text_center(80, 8, "SLEEZE", COL_WHITE);
    draw_text_center(150, 8, "DISCO", COL_RED);
    draw_text_center(230, 3, "BEAT KUNE DO", COL_GOLD);
    draw_text_center(270, 2, "A RHYTHM BRAWLER FOR PS VITA", COL_GREY);
    draw_text_center(300, 2, "INSPIRED BY DEAD AS DISCO - ORIGINAL GAME", COL_GREY);
    const char *items[4] = {"STORY", "INFINITE DISCO", "MY MUSIC", "HOW TO PLAY"};
    for (int i = 0; i < 4; i++) {
        int y = 350 + i * 36;
        if (g_menu == i) { fill_rect(330, y - 6, 300, 30, COL_RED_DK); draw_text(340, y, 3, items[i], COL_GOLD); }
        else draw_text(340, y, 3, items[i], COL_WHITE);
    }
    char s[64];
    snprintf(s, sizeof(s), "HI-SCORE %d   FANS %d", g_save.hi_score, g_save.fans);
    draw_text_center(500, 2, s, COL_PINK);
    if (g_save.vex_beaten) draw_text_center(524, 2, "* VEX BEATEN - PERFECT STRIKES UNLOCKED *", COL_GOLD);
    draw_text_center(510, 1, "PRESS X TO SELECT - START = PAUSE IN FIGHT", COL_GREY);
}

static void draw_howto(void) {
    clear_screen(COL_BG);
    draw_text_center(40, 4, "HOW TO PLAY", COL_GOLD);
    const char *lines[] = {
        "HITS LAND ON THE BEAT. PERFECT +-60MS = +50% DMG.",
        "GOOD +-120MS = +10%. OFF-BEAT HITS ARE NOT PENALISED.",
        "",
        "SQUARE - PUNCH    TRIANGLE - KICK",
        "CIRCLE - DRUMSTICK THROW (RANGED)",
        "CROSS - DODGE (I-FRAMES)",
        "L - COUNTER WHEN THE ENEMY FLASHES RED",
        "R + SQUARE - TAKEDOWN WHEN THE METER IS FULL",
        "",
        "BRUISERS NEED 4 PERFECT HITS TO STUN.",
        "CHARGERS TELEGRAPH - DODGE, DON'T TRADE.",
        "BEAT VEX TO UNLOCK PERFECT STRIKES.",
        "",
        "MY MUSIC: DROP WAVS IN UX0:DATA/SLEEZEDISCO/MUSIC/",
        "AND PICK THEIR BPM ON THE MODE SCREEN.",
    };
    for (int i = 0; lines[i]; i++) draw_text_center(110 + i * 26, 2, lines[i], COL_WHITE);
    draw_text_center(500, 2, "PRESS CIRCLE TO GO BACK", COL_GREY);
}

static void draw_results(int won) {
    clear_screen(COL_BG);
    draw_text_center(60, 5, won ? "ENCORE!" : "LAST SONG...", won ? COL_GOLD : COL_RED);
    char b[64];
    snprintf(b, sizeof(b), "SCORE %d", g_score);
    draw_text_center(150, 4, b, COL_WHITE);
    snprintf(b, sizeof(b), "MAX COMBO X%d", g_max_combo);
    draw_text_center(200, 3, b, COL_WHITE);
    int total = g_perfect + g_good + g_off;
    int pct = total ? (g_perfect * 100 / total) : 0;
    snprintf(b, sizeof(b), "PERFECT %d  GOOD %d  OFF %d  (%d%% PERFECT)", g_perfect, g_good, g_off, pct);
    draw_text_center(250, 2, b, COL_WHITE);
    snprintf(b, sizeof(b), "FANS EARNED %d   TOTAL FANS %d", g_score / 100, g_save.fans);
    draw_text_center(290, 2, b, COL_PINK);
    if (won && g_mode == 0 && g_chapter == 2)
        draw_text_center(340, 3, "VEX BEATEN! PERFECT STRIKES UNLOCKED!", COL_GOLD);
    if (won && g_mode == 0 && g_chapter < 2) {
        snprintf(b, sizeof(b), "CHAPTER CLEAR - NEXT: %s", SONGS[g_chapter + 1].name);
        draw_text_center(340, 2, b, COL_CYAN);
    }
    draw_text_center(430, 2, "X - PLAY AGAIN    CIRCLE - TITLE", COL_GREY);
}

/* ---------- per-frame update ---------- */
static void update_fight(void) {
    if (pressed(SCE_CTRL_START)) { g_state = ST_PAUSE; return; }
    /* movement */
    if (pad.buttons & SCE_CTRL_LEFT) { g_pl.x -= 5; g_pl.facing = -1; }
    if (pad.buttons & SCE_CTRL_RIGHT) { g_pl.x += 5; g_pl.facing = 1; }
    if (pad.buttons & SCE_CTRL_UP) g_pl.y -= 3;
    if (pad.buttons & SCE_CTRL_DOWN) g_pl.y += 3;
    if (g_pl.x < 60) g_pl.x = 60;
    if (g_pl.x > 900) g_pl.x = 900;
    if (g_pl.y < 340) g_pl.y = 340;
    if (g_pl.y > 470) g_pl.y = 470;
    if (pressed(SCE_CTRL_SQUARE) && (pad.buttons & SCE_CTRL_RTRIGGER)) { player_takedown(); return; }
    if (pressed(SCE_CTRL_SQUARE)) player_attack(0);
    if (pressed(SCE_CTRL_TRIANGLE)) player_attack(1);
    if (pressed(SCE_CTRL_CIRCLE)) player_attack(2);
    if (pressed(SCE_CTRL_CROSS) && now_us() >= g_pl.dodge_cd) {
        g_pl.dodge_until = now_us() + 350000;
        g_pl.dodge_cd = now_us() + 700000;
        g_pl.x += g_pl.facing * 70;
        if (g_pl.x < 60) g_pl.x = 60;
        if (g_pl.x > 900) g_pl.x = 900;
    }
    if (pressed(SCE_CTRL_LTRIGGER)) {
        /* counter: if any enemy is winding up, stun them */
        int hit = 0;
        for (int i = 0; i < MAX_ENEMIES; i++) {
            Enemy *e = &g_enemies[i];
            if (e->hp > 0 && e->state == 1) {
                e->state = 3; e->state_t = now_us();
                g_score += 300; g_combo += 2;
                strcpy(g_judge, "COUNTER!");
                g_judge_t = now_us();
                hit = 1;
            }
        }
        if (hit) g_pl.meter += 15;
        if (g_pl.meter > 100) g_pl.meter = 100;
        g_pl.counter_until = now_us() + 200000;
    }
    update_enemies();
}

int main(void) {
    scePowerSetArmClockFrequency(444);
    sceCtrlSetSamplingMode(SCE_CTRL_MODE_ANALOG);
    save_load();
    srand(1337);
    g_px = fb[0];

    while (1) {
        prev_pad = pad;
        sceCtrlPeekBufferPositive(0, &pad, 1);

        if (g_state == ST_TITLE) {
            if (pressed(SCE_CTRL_UP)) { g_menu = (g_menu + 3) % 4; }
            if (pressed(SCE_CTRL_DOWN)) { g_menu = (g_menu + 1) % 4; }
            if (pressed(SCE_CTRL_CROSS)) {
                if (g_menu == 0) { g_chapter = 0; start_fight(0, 0, SONGS[0].bpm); }
                else if (g_menu == 1) { start_fight(1, 1, 120); }
                else if (g_menu == 2) { g_menu = 0; g_state = ST_MODES; }
                else g_state = ST_HOWTO;
            }
            draw_title();
        } else if (g_state == ST_MODES) {
            /* My Music BPM picker */
            clear_screen(COL_BG);
            draw_text_center(60, 4, "MY MUSIC", COL_GOLD);
            draw_text_center(120, 2, "PICK A BPM - THE SYNTH TRACK FOLLOWS IT", COL_WHITE);
            draw_text_center(150, 2, "ON VITA, DROP YOUR OWN WAVS IN", COL_GREY);
            draw_text_center(175, 2, "UX0:DATA/SLEEZEDISCO/MUSIC/", COL_GREY);
            const int bpms[4] = {90, 110, 130, 150};
            for (int i = 0; i < 4; i++) {
                char b[16]; snprintf(b, sizeof(b), "%d BPM", bpms[i]);
                int y = 230 + i * 40;
                if (g_menu == i) { fill_rect(400, y - 6, 160, 30, COL_RED_DK); draw_text(420, y, 3, b, COL_GOLD); }
                else draw_text(420, y, 3, b, COL_WHITE);
            }
            if (pressed(SCE_CTRL_UP)) g_menu = (g_menu + 3) % 4;
            if (pressed(SCE_CTRL_DOWN)) g_menu = (g_menu + 1) % 4;
            if (pressed(SCE_CTRL_CROSS)) { int bpm = (int[]){90, 110, 130, 150}[g_menu]; start_fight(2, 1, bpm); }
            if (pressed(SCE_CTRL_CIRCLE)) { g_menu = 2; g_state = ST_TITLE; }
        } else if (g_state == ST_HOWTO) {
            if (pressed(SCE_CTRL_CIRCLE)) g_state = ST_TITLE;
            draw_howto();
        } else if (g_state == ST_FIGHT) {
            update_fight();
            if (g_state == ST_FIGHT) draw_fight();
        } else if (g_state == ST_PAUSE) {
            clear_screen(COL_BG);
            draw_text_center(200, 5, "PAUSED", COL_WHITE);
            draw_text_center(280, 2, "START - RESUME    SELECT - QUIT TO TITLE", COL_GREY);
            if (pressed(SCE_CTRL_START)) g_state = ST_FIGHT;
            if (pressed(SCE_CTRL_SELECT)) { audio_stop(); g_state = ST_TITLE; }
        } else if (g_state == ST_WIN || g_state == ST_LOSE) {
            int won = (g_state == ST_WIN);
            draw_results(won);
            if (pressed(SCE_CTRL_CROSS)) {
                if (won && g_mode == 0 && g_chapter < 2) start_fight(0, g_chapter + 1, SONGS[g_chapter + 1].bpm);
                else if (g_mode == 0) start_fight(0, g_chapter, SONGS[g_chapter].bpm);
                else if (g_mode == 1) start_fight(1, 1, 120);
                else start_fight(2, 1, g_bpm);
            }
            if (pressed(SCE_CTRL_CIRCLE)) { g_menu = 0; g_state = ST_TITLE; }
        }
        flip();
    }
    return 0;
}
