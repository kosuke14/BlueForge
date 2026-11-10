#include "LC3Bridge.h"
#include "lc3.h"

#include <stdlib.h>

struct LC3Context {
    int channels;
    int sampleRate;
    int dt_us;
    int bitrate;
    int perChannelBytes;
    int totalBytes;
    int samplesPerFrame;
    lc3_encoder_t *enc;
    void **encMem;
    lc3_decoder_t *dec;
    void **decMem;
};

LC3Context *lc3_create(int sampleRate, int channels, int bitrate, int frameDurationUs) {
    if (channels < 1 || channels > 8) return NULL;
    if (frameDurationUs == 0) frameDurationUs = 10000;
    LC3Context *ctx = calloc(1, sizeof(LC3Context));
    if (!ctx) return NULL;
    ctx->channels = channels;
    ctx->sampleRate = sampleRate;
    ctx->dt_us = frameDurationUs;
    ctx->bitrate = bitrate;

    ctx->samplesPerFrame = lc3_frame_samples(frameDurationUs, sampleRate);
    if (ctx->samplesPerFrame <= 0) { free(ctx); return NULL; }

    ctx->totalBytes = lc3_hr_frame_block_bytes(false, frameDurationUs, sampleRate, channels, bitrate);
    if (ctx->totalBytes <= 0) { free(ctx); return NULL; }
    ctx->perChannelBytes = ctx->totalBytes / channels;
    if (ctx->perChannelBytes <= 0) { free(ctx); return NULL; }

    ctx->enc = calloc(channels, sizeof(lc3_encoder_t));
    ctx->encMem = calloc(channels, sizeof(void *));
    ctx->dec = calloc(channels, sizeof(lc3_decoder_t));
    ctx->decMem = calloc(channels, sizeof(void *));
    if (!ctx->enc || !ctx->encMem || !ctx->dec || !ctx->decMem) {
        free(ctx->enc); free(ctx->encMem); free(ctx->dec); free(ctx->decMem); free(ctx);
        return NULL;
    }

    for (int c = 0; c < channels; c++) {
        unsigned esz = lc3_encoder_size(frameDurationUs, sampleRate);
        ctx->encMem[c] = calloc(1, esz);
        ctx->enc[c] = lc3_setup_encoder(frameDurationUs, sampleRate, 0, ctx->encMem[c]);
        if (!ctx->enc[c]) {
            free(ctx); return NULL;
        }
        unsigned dsz = lc3_decoder_size(frameDurationUs, sampleRate);
        ctx->decMem[c] = calloc(1, dsz);
        ctx->dec[c] = lc3_setup_decoder(frameDurationUs, sampleRate, 0, ctx->decMem[c]);
        if (!ctx->dec[c]) {
            free(ctx); return NULL;
        }
    }
    return ctx;
}

void lc3_destroy(LC3Context *ctx) {
    if (!ctx) return;
    for (int c = 0; c < ctx->channels; c++) {
        free(ctx->encMem[c]);
        free(ctx->decMem[c]);
    }
    free(ctx->enc);
    free(ctx->encMem);
    free(ctx->dec);
    free(ctx->decMem);
    free(ctx);
}

int lc3_encode_frame(LC3Context *ctx, const int16_t *pcm, int pcmBytes,
                     unsigned char *out, int outCapacity) {
    if (!ctx || !pcm || !out) return -1;
    int samplesPerFrame = ctx->samplesPerFrame;
    int channels = ctx->channels;
    (void)pcmBytes;
    if (outCapacity < ctx->totalBytes) return -1;
    for (int c = 0; c < channels; c++) {
        int ret = lc3_encode(ctx->enc[c], LC3_PCM_FORMAT_S16,
                            pcm + c, channels, ctx->perChannelBytes,
                            out + c * ctx->perChannelBytes);
        if (ret != 0) return -1;
    }
    return ctx->totalBytes;
}

int lc3_decode_frame(LC3Context *ctx, const unsigned char *in, int inLen,
                     int16_t *out, int outCapacity) {
    if (!ctx || !in || !out) return -1;
    int channels = ctx->channels;
    (void)inLen;
    for (int c = 0; c < channels; c++) {
        int ret = lc3_decode(ctx->dec[c],
                            in + c * ctx->perChannelBytes,
                            ctx->perChannelBytes,
                            LC3_PCM_FORMAT_S16,
                            out + c, channels);
        if (ret < 0) return -1;
    }
    int pcmBytes = ctx->samplesPerFrame * channels * 2;
    if (pcmBytes > outCapacity) pcmBytes = outCapacity;
    return pcmBytes;
}

int lc3_frame_samples_count(LC3Context *ctx) {
    return ctx ? ctx->samplesPerFrame : 0;
}
