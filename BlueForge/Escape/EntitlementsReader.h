//
//  EntitlementsReader.h
//  BlueForge
//
//  Derived from huamidev/GestaltX GXEntitlementsReader (GPL-3.0), itself
//  adapted from LCSign's LCEntitlementsReader.
//  https://github.com/huamidev/GestaltX
//
//  Runtime App Group discovery: reads the effective entitlements of this
//  process (SecTask first, then the main image's Mach-O code signature). This
//  is what makes the escape work under re-signing hosts such as
//  LiveContainer / SideStore / AltStore, whose injected group differs from
//  the development one.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

#ifndef EntitlementsReader_h
#define EntitlementsReader_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface EntitlementsReader : NSObject
/// App Groups this process is effectively signed with (and that have an
/// accessible container), in a stable preferred order.
+ (NSArray<NSString *> *)usableAppGroups;
/// Mach-O / fat binary + code-signature entitlement parser (bounds-checked).
+ (nullable NSDictionary *)entitlementsInMachOData:(NSData *)data;
@end

NS_ASSUME_NONNULL_END

#endif /* EntitlementsReader_h */
