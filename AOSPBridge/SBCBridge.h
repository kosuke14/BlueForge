#ifndef SBCBridge_h
#define SBCBridge_h

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct sbc_struct SBCContext;

SBCContext *sbc_create(int sampleRate, int channels, int bitpool,
                       int blocks, int subbands, int allocation,
                       int channelMode);
void sbc_destroy(SBCContext *ctx);

/* Encode one frame. pcm must contain at least sbc_codesize() bytes (int16 interleaved).
   Returns number of encoded bytes written to out, or -1 on error. */
int sbc_encode_frame(SBCContext *ctx, const int16_t *pcm, int pcmBytes,
                     unsigned char *out, int outCapacity);

/* Decode one frame. Returns number of PCM bytes written to out, or -1 on error. */
int sbc_decode_frame(SBCContext *ctx, const unsigned char *in, int inLen,
                     int16_t *out, int outCapacity);

size_t sbc_frame_length(SBCContext *ctx);
size_t sbc_codesize(SBCContext *ctx);

#ifdef __cplusplus
}
#endif

#endif /* SBCBridge_h */
