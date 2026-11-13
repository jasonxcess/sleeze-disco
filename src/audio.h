#ifndef SLEEZE_AUDIO_H
#define SLEEZE_AUDIO_H

#include <stdint.h>

#define AUDIO_SR 48000
#define AUDIO_CH 2

/* One original synth track. No licensed music, no audio files:
   everything is generated from oscillators + noise at load time. */
typedef struct {
    char name[48];
    int bpm;
    int bars;              /* bars generated (loops) */
    int total_samples;     /* per channel */
    int16_t *pcm;          /* interleaved stereo, total_samples * 2 */
} Track;

/* Generate a track. scale_root is a MIDI note number for the bass root.
   style: 0 = alley (100bpm, dark), 1 = dive bar (120bpm), 2 = idol (140bpm, aggressive) */
Track *audio_gen_track(const char *name, int bpm, int bars, int scale_root, int style);
void audio_free_track(Track *t);

/* Playback position in samples, updated by the audio thread. */
extern volatile int g_audio_pos;
extern volatile int g_audio_playing;

int audio_start(Track *t);
void audio_stop(void);

#endif
