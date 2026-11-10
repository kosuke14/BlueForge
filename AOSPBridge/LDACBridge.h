//
//  LDACBridge.h
//  BlueForge
//
//  Objective-C++ façade over AOSP external/libldac.
//  Build notes:
//    1. Add AOSP source tree (external/libldac) to the target.
//    2. Compile this file as Objective-C++ (.mm).
//    3. Link libldacBT_enc / libldacBT_dec.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LDACBridge : NSObject

/// Create an encoder. Returns nil on failure.
- (nullable instancetype)initWithSampleRate:(int)sampleRate
                                    channels:(int)channels
                                     bitrate:(int)bitrate;

/// Encode a chunk of interleaved Int16 PCM. Returns encoded frame or nil.
- (nullable NSData *)encodePCM:(NSData *)pcm;

/// Reset encoder state.
- (void)reset;

@end

NS_ASSUME_NONNULL_END
