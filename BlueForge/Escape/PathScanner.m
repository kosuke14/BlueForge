//
//  PathScanner.m
//  BlueForge
//
//  Derived from forcequitOS/worse_query pathleak (GPL-3.0) by Taj C (forcequit).
//  https://github.com/forcequitOS/worse_query
//
//  Additions over the original:
//    - prefix matching tolerates both "/var/..." and "/private/var/..." forms
//      (fsgetpath may return either; worse_query's own UI defaults to
//      "/private/var/..."),
//    - statfs fallback: if the sandbox refuses statfs on the target, the data
//      volume fsid is taken from a path the app can always stat,
//    - chunked parallel scan (dispatch_apply) to cut wall time on 18M+ inodes.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

#import <Foundation/Foundation.h>
#include <sys/fsgetpath.h>
#include <sys/mount.h>
#include <limits.h>
#include <string.h>
#include <dispatch/dispatch.h>
#import "PathScanner.h"

static BOOL BFMatchPrefix(const char *buffer, const char *prefix, size_t prefix_length) {
    if (strncmp(buffer, prefix, prefix_length) != 0) return NO;
    if (buffer[prefix_length] != '/') return NO;
    if (strchr(buffer + prefix_length + 1, '/')) return NO;
    return YES;
}

NSArray<NSString *> *PathScannerEnumerateDeep(NSArray<NSString *> *prefixes,
                                              uint64_t max_inode,
                                              NSArray<NSString *> *keywords,
                                              NSUInteger maxResults) {
    if (prefixes.count == 0 || max_inode < 1 || keywords.count == 0) return nil;

    struct statfs sfs;
    const char *fallbacks[] = { "/private/var/mobile", "/var/mobile" };
    BOOL ok = NO;
    for (size_t i = 0; i < sizeof(fallbacks) / sizeof(fallbacks[0]); i++) {
        if (statfs(fallbacks[i], &sfs) == 0) { ok = YES; break; }
    }
    if (!ok) return nil;
    fsid_t fsid = sfs.f_fsid;

    NSMutableArray<NSString *> *normPrefixes = [NSMutableArray array];
    for (NSString *raw in prefixes) {
        NSString *dir = raw;
        while (dir.length > 1 && [dir hasSuffix: @"/"]) {
            dir = [dir substringToIndex: dir.length - 1];
        }
        [normPrefixes addObject: dir];
        if ([dir hasPrefix: @"/var/"]) [normPrefixes addObject: [@"/private" stringByAppendingString: dir]];
        else if ([dir hasPrefix: @"/private/var/"]) [normPrefixes addObject: [dir substringFromIndex: 8]];
    }

    NSMutableArray<NSString *> *lowerKeywords = [NSMutableArray array];
    for (NSString *kw in keywords) [lowerKeywords addObject: kw.lowercaseString];

    NSFileManager *files = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    __block BOOL overflow = NO;

    uint64_t chunkSize = 262144;
    uint64_t chunkCount = (max_inode + chunkSize - 1) / chunkSize;

    dispatch_apply((NSUInteger)chunkCount,
                   dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0),
                   ^(size_t chunk) {
        if (overflow) return;
        uint64_t start = (uint64_t)chunk * chunkSize + 1;
        uint64_t end = ((uint64_t)chunk + 1) * chunkSize;
        if (end > max_inode) end = max_inode;

        char buffer[PATH_MAX];
        fsid_t volFSID = fsid;
        NSMutableArray<NSString *> *local = [NSMutableArray array];
        for (uint64_t inode = start; inode <= end; inode++) {
            ssize_t n = fsgetpath(buffer, sizeof(buffer), &volFSID, inode);
            if (n <= 0) continue;

            NSString *path = [files stringWithFileSystemRepresentation: buffer length: strlen(buffer)];
            if (!path) continue;
            BOOL under = NO;
            for (NSString *prefix in normPrefixes) {
                if ([path hasPrefix: prefix]) { under = YES; break; }
            }
            if (!under) continue;
            NSString *lowered = path.lowercaseString;
            BOOL hit = NO;
            for (NSString *kw in lowerKeywords) {
                if ([lowered containsString: kw]) { hit = YES; break; }
            }
            if (!hit) continue;

            [local addObject: path];
            if (local.count + result.count >= maxResults) { overflow = YES; return; }
        }
        if (local.count > 0) {
            @synchronized (result) {
                [result addObjectsFromArray: local];
                if (result.count >= maxResults) overflow = YES;
            }
        }
    });

    return [result sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a compare:b];
    }];
}

NSArray<NSString *> *PathScannerEnumerate(NSString *path, uint64_t max_inode) {
    if (path.length == 0 || max_inode < 1) return nil;
    NSString *dir = path;
    while (dir.length > 1 && [dir hasSuffix: @"/"]) {
        dir = [dir substringToIndex: dir.length - 1];
    }

    struct statfs sfs;
    if (statfs(dir.fileSystemRepresentation, &sfs) != 0) {
        // The sandbox may refuse statfs on the target. Everything under /var
        // lives on the same data volume; take its fsid from our tmp dir.
        const char *fallbacks[] = {
            "/private/var/mobile",
            "/var/mobile",
            [NSTemporaryDirectory() fileSystemRepresentation],
        };
        BOOL ok = NO;
        for (size_t i = 0; i < sizeof(fallbacks) / sizeof(fallbacks[0]); i++) {
            if (statfs(fallbacks[i], &sfs) == 0) { ok = YES; break; }
        }
        if (!ok) return nil;
    }
    fsid_t fsid = sfs.f_fsid;

    char prefix[PATH_MAX];
    char privatePrefix[PATH_MAX];
    if (![dir getFileSystemRepresentation: prefix maxLength: sizeof(prefix)]) return nil;
    size_t prefix_length = strlen(prefix);
    if (prefix_length == 1 && prefix[0] == '/') prefix_length = 0;

    // Second accepted form: /private-prefixed paths (and vice versa).
    if (prefix_length > 0 && strncmp(prefix, "/var/", 5) == 0) {
        snprintf(privatePrefix, sizeof(privatePrefix), "/private%s", prefix);
    } else if (prefix_length > 8 && strncmp(prefix, "/private/var/", 13) == 0) {
        snprintf(privatePrefix, sizeof(privatePrefix), "%s", prefix + 8);
    } else {
        privatePrefix[0] = '\0';
    }
    size_t privateLength = strlen(privatePrefix);

    NSFileManager *files = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *result = [NSMutableArray array];

    char *prefixHeap = strdup(prefix);
    char *privatePrefixHeap = privateLength > 0 ? strdup(privatePrefix) : NULL;

    uint64_t chunkSize = 262144;
    uint64_t chunkCount = (max_inode + chunkSize - 1) / chunkSize;

    dispatch_apply((NSUInteger)chunkCount,
                   dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0),
                   ^(size_t chunk) {
        uint64_t start = (uint64_t)chunk * chunkSize + 1;
        uint64_t end = ((uint64_t)chunk + 1) * chunkSize;
        if (end > max_inode) end = max_inode;

        char buffer[PATH_MAX];
        fsid_t volFSID = fsid;
        NSMutableArray<NSString *> *local = [NSMutableArray array];
        for (uint64_t inode = start; inode <= end; inode++) {
            ssize_t n = fsgetpath(buffer, sizeof(buffer), &volFSID, inode);
            if (n <= 0) continue;

            BOOL matched = BFMatchPrefix(buffer, prefixHeap, prefix_length);
            if (!matched && privatePrefixHeap) {
                matched = BFMatchPrefix(buffer, privatePrefixHeap, privateLength);
            }
            if (!matched) continue;

            NSString *string = [files stringWithFileSystemRepresentation: buffer length: strlen(buffer)];
            if (string) [local addObject: string];
        }
        if (local.count > 0) {
            @synchronized (result) {
                [result addObjectsFromArray: local];
            }
        }
    });

    free(prefixHeap);
    free(privatePrefixHeap);

    return [result sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a compare:b];
    }];
}
