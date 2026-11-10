#include "LDACBridge.h"

#include "ldacBT.h"
#include "ldacdec.h"

#include <stdlib.h>

struct LDACContext {
    HANDLE_LDAC_BT enc;
    ldacdec_t *dec;
    int channels;
    int sampleRate;
};

LDACContext *ldac_create(int sampleRate, int channels, int bitrate) {
    LDACContext *ctx = calloc(1, sizeof(LDACContext));
    if (!ctx) return NULL;
    ctx->channels = channels;
    ctx->sampleRate = sampleRate;

    int eqmid = LDACBT_EQMID_HQ;
    if (bitrate < 600000) eqmid = LDACBT_EQMID_MQ;
    else if (bitrate < 900000) eqmid = LDACBT_EQMID_SQ;

    int cm = (channels == 1) ? LDACBT_CHANNEL_MODE_MONO : LDACBT_CHANNEL_MODE_STEREO;
    int mtu = 1024;

    ctx->enc = ldacBT_get_handle();
    if (!ctx->enc) { free(ctx); return NULL; }
    if (ldacBT_init_handle_encode(ctx->enc, mtu, eqmid, cm,
                                 LDACBT_SMPL_FMT_S16, sampleRate) != 0) {
        ldacBT_free_handle(ctx->enc);
        free(ctx);
        return NULL;
    }

    ctx->dec = calloc(1, sizeof(ldacdec_t));
    if (!ctx->dec) {
        ldacBT_free_handle(ctx->enc);
        free(ctx);
        return NULL;
    }
    ldacdecInit(ctx->dec);
    return ctx;
}

void ldac_destroy(LDACContext *ctx) {
    if (!ctx) return;
    if (ctx->enc) ldacBT_free_handle(ctx->enc);
    free(ctx->dec);
    free(ctx);
}

int ldac_encode(LDACContext *ctx, const int16_t *pcm, int pcmBytes,
                unsigned char *out, int outCapacity) {
    if (!ctx || !ctx->enc || !pcm || !out) return -1;
    int offset = 0;
    while (offset < pcmBytes) {
        int pcm_used = 0, stream_sz = 0, frame_num = 0;
        int ret = ldacBT_encode(ctx->enc, (void *)((char *)pcm + offset),
                               &pcm_used, out, &stream_sz, &frame_num);
        if (ret != 0) return -1;
        if (pcm_used > 0) offset += pcm_used;
        else offset += 128 * ctx->channels * 2;
        if (stream_sz > 0) return stream_sz;
        if (offset >= pcmBytes) break;
    }
    (void)outCapacity;
    return -1;
}

int ldac_decode(LDACContext *ctx, const unsigned char *in, int inLen,
                int16_t *out, int outCapacity) {
    if (!ctx || !ctx->dec || !in || !out) return -1;
    int totalPcm = 0;
    int offset = 0;
    while (offset < inLen) {
        int bytesUsed = 0;
        int16_t *dst = (int16_t *)((char *)out + totalPcm);
        int ret = ldacDecode(ctx->dec, (uint8_t *)in + offset, dst, &bytesUsed);
        if (ret != 0) break;
        int samples = ctx->dec->frame.frameSamples;
        int ch = ctx->dec->frame.channelCount;
        if (ch <= 0) ch = ctx->channels;
        int pcmBytes = samples * ch * 2;
        if (totalPcm + pcmBytes > outCapacity) {
            pcmBytes = outCapacity - totalPcm;
            if (pcmBytes <= 0) break;
        }
        totalPcm += pcmBytes;
        if (bytesUsed <= 0) break;
        offset += bytesUsed;
        if (offset >= inLen) break;
    }
    return totalPcm > 0 ? totalPcm : -1;
}
