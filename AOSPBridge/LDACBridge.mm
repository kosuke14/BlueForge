//
//  LDACBridge.mm
//

#import "LDACBridge.h"

// AOSP headers (add external/libldac/inc to header search paths):
// #include "ldacBT.h"

@implementation LDACBridge {
    // HANDLE_LDAC_BT _handle;
    int _sampleRate;
    int _channels;
    int _bitrate;
}

- (nullable instancetype)initWithSampleRate:(int)sampleRate
                                    channels:(int)channels
                                     bitrate:(int)bitrate {
    self = [super init];
    if (!self) return nil;
    _sampleRate = sampleRate;
    _channels = channels;
    _bitrate = bitrate;

    // TODO (AOSP integration):
    // _handle = ldacBT_get_handle();
    // if (!_handle) return nil;
    // int eqmid = LDACBT_EQMID_MQ; // or HQ/SQ
    // ldacBT_init_handle_encode(_handle, eqmid, ...);
    // ldacBT_set_bitrate(_handle, bitrate);
    return self;
}

- (nullable NSData *)encodePCM:(NSData *)pcm {
    // TODO:
    // int frameBytes = ...;
    // NSMutableData *out = [NSMutableData dataWithLength:frameBytes];
    // int ret = ldacBT_encode(_handle, (const unsigned char *)pcm.bytes, (unsigned char *)out.mutableBytes, &frameBytes);
    // if (ret < 0) return nil;
    // [out setLength:frameBytes];
    // return out;
    return nil;
}

- (void)reset {
    // TODO: ldacBT_reset_handle? (re-init)
}

- (void)dealloc {
    // TODO: ldacBT_free_handle(_handle);
}

@end
