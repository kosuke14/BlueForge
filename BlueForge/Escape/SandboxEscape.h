//
//  SandboxEscape.h
//  BlueForge
//
//  Derived from forcequitOS/worse_query (GPL-3.0) by Taj C (forcequit).
//  https://github.com/forcequitOS/worse_query
//
//  Consume a kernel sandbox extension for an arbitrary path by querying
//  containermanagerd for an App Group container whose Library/Caches symlink
//  points at the target. The returned handle grants the process access to the
//  target path until it is released.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

#ifndef SandboxEscape_h
#define SandboxEscape_h

#import <Foundation/Foundation.h>
#import <stdint.h>
#import <stdbool.h>

// Consume a sandbox extension granting access to `target`.
//   target      - absolute path to gain access to (must exist unless create_dir)
//   group       - App Group identifier owned by this app (entitlement required)
//   alt_flags   - iOS 26.x App Group containers need a different flag value
//   create_dir  - skip the lstat existence check on target
// Returns a positive handle (>0) on success, or a negative error code:
//   -1 App Group unavailable, -2 dlsym failure, -3 query creation failure,
//   -4 symlink failure, -5 query rejected, -6 kernel refused issue,
//   -255 target missing.
int64_t SandboxExtensionConsume(NSString *target, NSString *group,
                                bool alt_flags, bool create_dir);

// Release a handle previously returned by SandboxExtensionConsume.
void SandboxExtensionRelease(int64_t handle);

#endif /* SandboxEscape_h */
