//
//  LC3Bridge.mm
//

#import "LC3Bridge.h"

// AOSP headers (add external/liblc3/include to header search paths):
// #include "lc3.h"

@implementation LC3Bridge {
    // lc3_encoder_t _enc;
    // lc3_decoder_t _dec;
    // void *_encMem; void *_decMem;
    int _sampleRate;
    int _channels;
    int _frameDurationUs;
    int _bitrate;
}

- (nullable instancetype)initWithSampleRate:(int)sampleRate
                                    channels:(int)channels
                              frameDurationUs:(int)frameDurationUs
                                     bitrate:(int)bitrate {
    self = [super init];
    if (!self) return nil;
    _sampleRate = sampleRate;
    _channels = channels;
    _frameDurationUs = frameDurationUs;
    _bitrate = bitrate;

    // TODO (AOSP integration):
    // size_t encSize = 0, decSize = 0;
    // lc3_encoder_create(sampleRate, channels, frameDurationUs, NULL, &encSize);
    // _encMem = calloc(1, encSize);
    // _enc = lc3_encoder_create(sampleRate, channels, frameDurationUs, _encMem, &encSize);
    // similarly for decoder
    return self;
}

- (nullable NSData *)encodePCM:(NSData *)pcm {
    // TODO:
    // size_t outSize = ...; // max frame size
    // NSMutableData *out = [NSMutableData dataWithLength:outSize];
    // lc3_encode(_enc, _bitrate, pcm.bytes, channels, out.mutableBytes, &outSize);
    // [out setLength:outSize];
    // return out;
    return nil;
}

- (nullable NSData *)decodeFrame:(NSData *)frame pcmBytes:(size_t *)outBytes {
    // TODO: lc3_decode(_dec, frame.bytes, frame.length, ...);
    return nil;
}

- (void)reset { }

- (void)dealloc {
    // free _encMem/_decMem
}

@end
