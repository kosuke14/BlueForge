//
//  PathScanner.h
//  BlueForge
//
//  Derived from forcequitOS/worse_query pathleak (GPL-3.0) by Taj C (forcequit).
//  https://github.com/forcequitOS/worse_query
//
//  Arbitrary path enumeration by brute-forcing inodes with fsgetpath().
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

#ifndef PathScanner_h
#define PathScanner_h

#import <Foundation/Foundation.h>

// Enumerate every direct child of `filter` on the same volume, up to
// `max_inode`. Slow (linear inode scan); cache the result.
NSArray<NSString *> *PathScannerEnumerate(NSString *filter, uint64_t max_inode);

// One full-volume inode scan; keep every path UNDER any of `prefixes`
// (either /var or /private/var form) that contains any of `keywords`
// (case-insensitive), at any depth. fsgetpath resolves paths without read
// permission, so files inside unreadable containers are discoverable by name.
NSArray<NSString *> *PathScannerEnumerateDeep(NSArray<NSString *> *prefixes,
                                              uint64_t max_inode,
                                              NSArray<NSString *> *keywords,
                                              NSUInteger maxResults);

#endif /* PathScanner_h */
