/* SLEEZE DISCO - procedural synth tracks.
   Original music only: kick / snare / hats / bass / lead, all synthesized
   with sine + square oscillators and filtered noise. No samples, no files.
   Vita side uses SceAudioOut; the same generator is mirrored in the
   web prototype (WebAudio oscillators) so the beat feels identical. */
#include "audio.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>

#ifdef __vita__
#include <psp2/audioout.h>
#include <psp2/kernel/threadmgr.h>
#include <psp2/kernel/processmgr.h>
#endif

volatile int g_audio_pos = 0;
volatile int g_audio_playing = 0;

static float frand(unsigned int *s) {
    *s = *s * 1664525u + 1013904223u;
    return ((*s >> 9) & 0x7FFFFF) / (float)0x7FFFFF * 2.0f - 1.0f;
}
static float midi_freq(int m) { return 440.0f * powf(2.0f, (m - 69) / 12.0f); }
static float clampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }

/* Minor-scale bass riffs, one per style. Values are semitone offsets. */
static const int RIFF_ALLEY[8] = {0, 0, 3, 5, 7, 5, 3, 2};
static const int RIFF_DIVE[8]  = {0, 7, 10, 7, 5, 3, 5, 7};
static const int RIFF_IDOL[8]  = {0, 0, 12, 10, 7, 10, 12, 15};

Track *audio_gen_track(const char *name, int bpm, int bars, int scale_root, int style) {
    Track *t = (Track *)calloc(1, sizeof(Track));
    if (!t) return NULL;
    strncpy(t->name, name, sizeof(t->name) - 1);
    t->bpm = bpm;
    t->bars = bars;
    double beat_sec = 60.0 / bpm;
    double bar_sec = beat_sec * 4.0;
    double total_sec = bar_sec * bars;
    t->total_samples = (int)(total_sec * AUDIO_SR);
    t->pcm = (int16_t *)malloc((size_t)t->total_samples * 2 * sizeof(int16_t));
    if (!t->pcm) { free(t); return NULL; }

    const int *riff = style == 2 ? RIFF_IDOL : (style == 1 ? RIFF_DIVE : RIFF_ALLEY);
    unsigned int rng = 0xC0FFEEu + (unsigned int)bpm * 7919u;
    float kick_phase = 0, bass_phase = 0, lead_phase = 0;
    float lp = 0; /* cheap one-pole lowpass for the noise / snare */

    for (int i = 0; i < t->total_samples; i++) {
        double time = (double)i / AUDIO_SR;
        double beat = time / beat_sec;
        int beat_i = (int)beat;
        double beat_f = beat - beat_i;              /* 0..1 inside the beat */
        int bar_i = beat_i / 4;
        int step = beat_i % 4;                      /* beat inside bar */
        double eighth = beat * 2.0;
        int eighth_i = (int)eighth;
        double eighth_f = eighth - eighth_i;

        float s = 0.0f;

        /* KICK: sine drop 150 -> 45 Hz on every beat, harder on 1 & 3. */
        {
            float env = expf((float)(-beat_f * 9.0));
            float f = 45.0f + 105.0f * env;
            kick_phase += 2.0f * 3.14159265f * f / AUDIO_SR;
            if (kick_phase > 6.283185f) kick_phase -= 6.283185f;
            s += sinf(kick_phase) * env * 0.95f;
        }
        /* SNARE: noise burst on beats 2 & 4. */
        if (step == 1 || step == 3) {
            float env = expf((float)(-beat_f * 14.0));
            float n = frand(&rng);
            lp += 0.25f * (n - lp);
            s += lp * env * 0.55f;
        }
        /* HATS: short noise ticks on every 8th, louder off-beat. */
        {
            float env = expf((float)(-eighth_f * 30.0));
            float n = frand(&rng);
            s += n * env * ((eighth_i & 1) ? 0.16f : 0.08f);
        }
        /* BASS: square-ish (sine + 3rd harmonic) on the riff, 8th notes. */
        {
            int semi = riff[(bar_i * 2 + (eighth_i % 2)) % 8];
            float f = midi_freq(scale_root + semi);
            bass_phase += 2.0f * 3.14159265f * f / AUDIO_SR;
            if (bass_phase > 6.283185f) bass_phase -= 6.283185f;
            float env = 0.55f + 0.45f * expf((float)(-eighth_f * 6.0));
            s += (sinf(bass_phase) + 0.3f * sinf(bass_phase * 3.0f)) * env * 0.30f;
        }
        /* LEAD: sparse minor arpeggio, only on some bars so it breathes. */
        if ((bar_i % 2) == 0 && style != 0) {
            int semi = riff[(eighth_i * 3) % 8] + 24;
            float f = midi_freq(scale_root + semi);
            lead_phase += 2.0f * 3.14159265f * f / AUDIO_SR;
            if (lead_phase > 6.283185f) lead_phase -= 6.283185f;
            float env = expf((float)(-eighth_f * 5.0));
            s += sinf(lead_phase) * env * 0.12f;
        }
        /* Idol track: extra distortion-ish grit on the downbeat. */
        if (style == 2 && beat_f < 0.08) s += frand(&rng) * 0.05f;

        s = clampf(s, -1.0f, 1.0f);
        int16_t v = (int16_t)(s * 28000);
        t->pcm[i * 2] = v;
        t->pcm[i * 2 + 1] = v;
    }
    return t;
}

void audio_free_track(Track *t) {
    if (!t) return;
    free(t->pcm);
    free(t);
}

#ifdef __vita__
static Track *g_cur = NULL;
static int g_port = -1;
static SceUID g_thread = -1;

static int audio_thread(SceSize args, void *argp) {
    (void)args; (void)argp;
    const int CHUNK = 1024; /* samples per channel per output call */
    int pos = 0;
    while (g_audio_playing && g_cur) {
        int remain = g_cur->total_samples - pos;
        int n = remain < CHUNK ? remain : CHUNK;
        /* sceAudioOutOutput expects len == the open length; pad the tail. */
        static int16_t buf[1024 * 2];
        for (int i = 0; i < n * 2; i++) buf[i] = g_cur->pcm[pos * 2 + i];
        for (int i = n * 2; i < CHUNK * 2; i++) buf[i] = 0;
        sceAudioOutOutput(g_port, buf);
        pos += n;
        g_audio_pos = pos;
        if (pos >= g_cur->total_samples) pos = 0; /* loop the track */
    }
    return 0;
}

int audio_start(Track *t) {
    audio_stop();
    if (!t) return -1;
    g_port = sceAudioOutOpenPort(SCE_AUDIO_OUT_PORT_TYPE_MAIN, 1024, AUDIO_SR,
                                 SCE_AUDIO_OUT_MODE_STEREO);
    if (g_port < 0) return -1;
    g_cur = t;
    g_audio_pos = 0;
    g_audio_playing = 1;
    g_thread = sceKernelCreateThread("sleeze_audio", audio_thread, 0x10000100,
                                     0x10000, 0, 0, NULL);
    if (g_thread < 0) { sceAudioOutReleasePort(g_port); g_port = -1; return -1; }
    sceKernelStartThread(g_thread, 0, NULL);
    return 0;
}

void audio_stop(void) {
    g_audio_playing = 0;
    if (g_thread >= 0) {
        sceKernelWaitThreadEnd(g_thread, NULL, NULL);
        sceKernelDeleteThread(g_thread);
        g_thread = -1;
    }
    if (g_port >= 0) { sceAudioOutReleasePort(g_port); g_port = -1; }
    g_cur = NULL;
    g_audio_pos = 0;
}
#else
/* Non-Vita (PC test harness): no audio output, position advances by caller. */
int audio_start(Track *t) { (void)t; g_audio_playing = 1; return 0; }
void audio_stop(void) { g_audio_playing = 0; }
#endif
