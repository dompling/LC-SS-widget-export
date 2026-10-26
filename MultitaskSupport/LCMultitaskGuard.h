// LCMultitaskGuard - diagnostic helpers for LC host-side multitask handling.
// Intentionally header-only so the existing Xcode target does not need project changes.
// This is NOT a guest-app tweak: LiveProcess scene setup runs in the LC host.
#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <math.h>

static inline BOOL LCMGIsValidSceneFrame(CGRect frame) {
    return isfinite(frame.origin.x) &&
           isfinite(frame.origin.y) &&
           isfinite(frame.size.width) &&
           isfinite(frame.size.height) &&
           frame.size.width > 0.0 &&
           frame.size.height > 0.0;
}

static inline void LCMGLogEvent(NSString *event,
                              NSString *bundleID,
                              NSString *containerID,
                              NSInteger pid,
                              NSString *detail) {
    // Avoid logging complete container identifiers or app content.
    NSString *shortContainer = containerID ?: @"none";
    if (shortContainer.length > 8) {
        shortContainer = [shortContainer substringToIndex:8];
    }
    NSLog(@"[LCMultitaskGuard] event=%@ bundle=%@ container=%@ pid=%ld detail=%@",
          event ?: @"unknown",
          bundleID ?: @"unknown",
          shortContainer,
          (long)pid,
          detail ?: @"none");
}
