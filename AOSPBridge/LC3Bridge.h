//
//  LC3Bridge.h
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LC3Bridge : NSObject

- (nullable instancetype)initWithSampleRate:(int)sampleRate
                                    channels:(int)channels
                              frameDurationUs:(int)frameDurationUs
                                     bitrate:(int)bitrate;

- (nullable NSData *)encodePCM:(NSData *)pcm;
- (nullable NSData *)decodeFrame:(NSData *)frame pcmBytes:(size_t *)outBytes;
- (void)reset;

@end

NS_ASSUME_NONNULL_END
