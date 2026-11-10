#ifndef LC3Bridge_h
#define LC3Bridge_h

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct LC3Context LC3Context;

LC3Context *lc3_create(int sampleRate, int channels, int bitrate, int frameDurationUs);
void lc3_destroy(LC3Context *ctx);

/* Encode one frame. Returns total encoded byte count or -1. */
int lc3_encode_frame(LC3Context *ctx, const int16_t *pcm, int pcmBytes,
                     unsigned char *out, int outCapacity);

/* Decode one frame. Returns PCM byte count or -1. */
int lc3_decode_frame(LC3Context *ctx, const unsigned char *in, int inLen,
                     int16_t *out, int outCapacity);

int lc3_frame_samples_count(LC3Context *ctx);

#ifdef __cplusplus
}
#endif

#endif /* LC3Bridge_h */
