//
//  EntitlementsReader.m
//  BlueForge
//
//  Derived from huamidev/GestaltX GXEntitlementsReader (GPL-3.0), itself
//  adapted from LCSign's LCEntitlementsReader.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/fat.h>
#import <libkern/OSByteOrder.h>
#import <dlfcn.h>
#import "EntitlementsReader.h"

static BOOL BFRange(NSUInteger offset, NSUInteger length, NSUInteger size) {
    return offset <= size && length <= size - offset;
}
static uint32_t BF32(const uint8_t *p, NSUInteger offset) {
    uint32_t value; memcpy(&value, p + offset, sizeof(value)); return value;
}
static uint64_t BF64(const uint8_t *p, NSUInteger offset) {
    uint64_t value; memcpy(&value, p + offset, sizeof(value)); return value;
}

static NSDictionary *BFSignature(const uint8_t *bytes, NSUInteger size) {
    if (size < 12 || OSSwapBigToHostInt32(BF32(bytes, 0)) != 0xfade0cc0) return nil;
    NSUInteger total = OSSwapBigToHostInt32(BF32(bytes, 4));
    NSUInteger count = OSSwapBigToHostInt32(BF32(bytes, 8));
    if (total < 12 || total > size || count > (total - 12) / 8) return nil;
    for (NSUInteger i = 0; i < count; i++) {
        NSUInteger offset = OSSwapBigToHostInt32(BF32(bytes, 12 + i * 8 + 4));
        if (!BFRange(offset, 8, total)) continue;
        uint32_t magic = OSSwapBigToHostInt32(BF32(bytes, offset));
        NSUInteger length = OSSwapBigToHostInt32(BF32(bytes, offset + 4));
        if (magic != 0xfade7171 || length < 8 || !BFRange(offset, length, total)) continue;
        NSData *plist = [NSData dataWithBytes:bytes + offset + 8 length:length - 8];
        id value = [NSPropertyListSerialization propertyListWithData:plist options:NSPropertyListImmutable format:NULL error:nil];
        if ([value isKindOfClass:NSDictionary.class]) return value;
    }
    return nil;
}

static NSDictionary *BFThin(const uint8_t *bytes, NSUInteger size) {
    if (size < sizeof(struct mach_header)) return nil;
    uint32_t magic = BF32(bytes, 0);
    BOOL is64 = magic == MH_MAGIC_64;
    if (!is64 && magic != MH_MAGIC) return nil;
    NSUInteger headerSize = is64 ? sizeof(struct mach_header_64) : sizeof(struct mach_header);
    if (size < headerSize) return nil;
    uint32_t count = BF32(bytes, 16), commandBytes = BF32(bytes, 20);
    if (!BFRange(headerSize, commandBytes, size) || count > commandBytes / sizeof(struct load_command)) return nil;
    NSUInteger cursor = headerSize, end = headerSize + commandBytes;
    for (uint32_t i = 0; i < count; i++) {
        if (!BFRange(cursor, sizeof(struct load_command), end)) return nil;
        uint32_t command = BF32(bytes, cursor), length = BF32(bytes, cursor + 4);
        if (length < sizeof(struct load_command) || !BFRange(cursor, length, end)) return nil;
        if (command == LC_CODE_SIGNATURE) {
            if (length < sizeof(struct linkedit_data_command)) return nil;
            NSUInteger offset = BF32(bytes, cursor + 8), signatureSize = BF32(bytes, cursor + 12);
            if (!BFRange(offset, signatureSize, size)) return nil;
            return BFSignature(bytes + offset, signatureSize);
        }
        cursor += length;
    }
    return nil;
}

static NSArray *BFEffectiveGroups(void) {
    typedef CFTypeRef (*CreateTask)(CFAllocatorRef);
    typedef CFTypeRef (*CopyEntitlement)(CFTypeRef, CFStringRef, CFErrorRef *);
    void *library = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY | RTLD_LOCAL);
    if (!library) return nil;
    CreateTask create = (CreateTask)dlsym(library, "SecTaskCreateFromSelf");
    CopyEntitlement copy = (CopyEntitlement)dlsym(library, "SecTaskCopyValueForEntitlement");
    NSArray *groups = nil;
    if (create && copy) {
        CFTypeRef task = create(NULL);
        if (task) {
            CFTypeRef value = copy(task, CFSTR("com.apple.security.application-groups"), NULL);
            if (value) {
                if (CFGetTypeID(value) == CFArrayGetTypeID()) groups = [(__bridge NSArray *)value copy];
                CFRelease(value);
            }
            CFRelease(task);
        }
    }
    dlclose(library);
    return groups;
}

@implementation EntitlementsReader

+ (NSDictionary *)entitlementsInMachOData:(NSData *)data {
    const uint8_t *bytes = data.bytes;
    NSUInteger size = data.length;
    if (size < sizeof(struct fat_header)) return nil;
    NSDictionary *thin = BFThin(bytes, size);
    if (thin) return thin;
    uint32_t magic = OSSwapBigToHostInt32(BF32(bytes, 0));
    BOOL is64 = magic == FAT_MAGIC_64;
    if (!is64 && magic != FAT_MAGIC) return nil;
    NSUInteger count = OSSwapBigToHostInt32(BF32(bytes, 4));
    NSUInteger stride = is64 ? sizeof(struct fat_arch_64) : sizeof(struct fat_arch);
    if (count > (size - sizeof(struct fat_header)) / stride) return nil;
    const struct mach_header *loaded = _dyld_get_image_header(0);
    for (NSUInteger i = 0; i < count; i++) {
        NSUInteger item = sizeof(struct fat_header) + i * stride;
        cpu_type_t cpu = (cpu_type_t)OSSwapBigToHostInt32(BF32(bytes, item));
        cpu_subtype_t subtype = (cpu_subtype_t)OSSwapBigToHostInt32(BF32(bytes, item + 4));
        if (loaded && (cpu != loaded->cputype || (subtype & ~CPU_SUBTYPE_MASK) != (loaded->cpusubtype & ~CPU_SUBTYPE_MASK))) continue;
        uint64_t offset = is64 ? OSSwapBigToHostInt64(BF64(bytes, item + 8)) : OSSwapBigToHostInt32(BF32(bytes, item + 8));
        uint64_t length = is64 ? OSSwapBigToHostInt64(BF64(bytes, item + 16)) : OSSwapBigToHostInt32(BF32(bytes, item + 12));
        if (offset > NSUIntegerMax || length > NSUIntegerMax || !BFRange((NSUInteger)offset, (NSUInteger)length, size)) continue;
        NSDictionary *value = BFThin(bytes + offset, (NSUInteger)length);
        if (value) return value;
    }
    return nil;
}

+ (NSArray<NSString *> *)usableAppGroups {
    NSArray *groups = BFEffectiveGroups();
    if (!groups) {
        const char *mainImage = _dyld_get_image_name(0);
        NSString *path = mainImage ? [NSString stringWithUTF8String:mainImage] : NSBundle.mainBundle.executablePath;
        NSData *binary = path ? [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil] : nil;
        NSDictionary *entitlements = binary ? [self entitlementsInMachOData:binary] : nil;
        id value = entitlements[@"com.apple.security.application-groups"];
        if ([value isKindOfClass:NSArray.class]) groups = value;
    }

    NSMutableOrderedSet<NSString *> *candidates = [NSMutableOrderedSet orderedSet];
    // Under re-signing hosts (LiveContainer etc.) the running bundle may be an
    // appex whose parent app holds the entitlements.
    NSBundle *bundle = NSBundle.mainBundle;
    if ([bundle.bundleURL.pathExtension isEqualToString:@"appex"]) {
        NSURL *parent = bundle.bundleURL.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent;
        bundle = [NSBundle bundleWithURL:parent] ?: bundle;
    }
    NSString *bundleGroup = [@"group." stringByAppendingString:bundle.bundleIdentifier ?: @""];
    if ([groups containsObject:bundleGroup]) [candidates addObject:bundleGroup];
    for (id group in [groups sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        return [[a description] compare:[b description]];
    }]) {
        if ([group isKindOfClass:NSString.class] && [group hasPrefix:@"group."]) [candidates addObject:group];
    }

    NSMutableArray<NSString *> *usable = [NSMutableArray array];
    for (NSString *candidate in candidates) {
        if ([[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:candidate]) {
            [usable addObject:candidate];
        }
    }
    return usable;
}

@end
