#include "SBCBridge.h"
#include "sbc.h"

#include <stdlib.h>

static int map_freq(int sr) {
    switch (sr) {
        case 16000: return SBC_FREQ_16000;
        case 32000: return SBC_FREQ_32000;
        case 44100: return SBC_FREQ_44100;
        default:    return SBC_FREQ_48000;
    }
}
static int map_blocks(int b) {
    if (b <= 4) return SBC_BLK_4;
    if (b <= 8) return SBC_BLK_8;
    if (b <= 12) return SBC_BLK_12;
    return SBC_BLK_16;
}
static int map_subbands(int s) { return (s == 4) ? SBC_SB_4 : SBC_SB_8; }
static int map_mode(int channels, int requested) {
    if (channels == 1) return SBC_MODE_MONO;
    if (requested >= 0) return requested;
    return SBC_MODE_JOINT_STEREO;
}
static int map_alloc(int a) { return (a == 0) ? SBC_AM_SNR : SBC_AM_LOUDNESS; }

SBCContext *sbc_create(int sampleRate, int channels, int bitpool,
                       int blocks, int subbands, int allocation,
                       int channelMode) {
    SBCContext *ctx = calloc(1, sizeof(SBCContext));
    if (!ctx) return NULL;
    if (sbc_init(ctx, 0) != 0) { free(ctx); return NULL; }
    ctx->frequency = (uint8_t)map_freq(sampleRate);
    ctx->blocks = (uint8_t)map_blocks(blocks);
    ctx->subbands = (uint8_t)map_subbands(subbands);
    ctx->mode = (uint8_t)map_mode(channels, channelMode);
    ctx->allocation = (uint8_t)map_alloc(allocation);
    ctx->bitpool = (uint8_t)bitpool;
    ctx->endian = SBC_LE;
    return ctx;
}

void sbc_destroy(SBCContext *ctx) {
    if (!ctx) return;
    sbc_finish(ctx);
    free(ctx);
}

int sbc_encode_frame(SBCContext *ctx, const int16_t *pcm, int pcmBytes,
                     unsigned char *out, int outCapacity) {
    if (!ctx || !pcm || !out) return -1;
    size_t codesize = sbc_get_codesize(ctx);
    if (pcmBytes < (int)codesize) return -1;
    size_t written = 0;
    ssize_t ret = sbc_encode(ctx, pcm, codesize, out, (size_t)outCapacity, &written);
    if (ret < 0) return (int)ret;
    if (written == 0) return -1;
    return (int)written;
}

int sbc_decode_frame(SBCContext *ctx, const unsigned char *in, int inLen,
                     int16_t *out, int outCapacity) {
    if (!ctx || !in || !out) return -1;
    size_t written = 0;
    ssize_t ret = sbc_decode(ctx, in, (size_t)inLen, out, (size_t)outCapacity, &written);
    if (ret < 0) return (int)ret;
    return (int)written;
}

size_t sbc_frame_length(SBCContext *ctx) { return ctx ? sbc_get_frame_length(ctx) : 0; }
size_t sbc_codesize(SBCContext *ctx) { return ctx ? sbc_get_codesize(ctx) : 0; }
