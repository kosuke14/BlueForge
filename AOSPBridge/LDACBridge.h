#ifndef LDACBridge_h
#define LDACBridge_h

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct LDACContext LDACContext;

LDACContext *ldac_create(int sampleRate, int channels, int bitrate);
void ldac_destroy(LDACContext *ctx);

/* Encode one frame (128 samples/channel). Returns encoded byte count or -1. */
int ldac_encode(LDACContext *ctx, const int16_t *pcm, int pcmBytes,
                unsigned char *out, int outCapacity);

/* Decode one frame. Returns PCM byte count or -1. */
int ldac_decode(LDACContext *ctx, const unsigned char *in, int inLen,
                int16_t *out, int outCapacity);

#ifdef __cplusplus
}
#endif

#endif /* LDACBridge_h */
