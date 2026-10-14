//
//  SystemActivity.swift
//  WalkAway
//

import Foundation
import CoreGraphics
import IOKit.pwr_mgt

enum SystemActivity {
    /// Seconds since the last keyboard, mouse, or trackpad input anywhere in the session. Needs no permissions.
    static func secondsSinceLastInput() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    /// True while an app keeps the display awake, which video players do during playback.
    /// Audio-only playback only blocks system sleep, so it doesn't count.
    static func isDisplaySleepPrevented() -> Bool {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
              let assertions = status?.takeRetainedValue() as? [String: Int] else { return false }
        return (assertions["PreventUserIdleDisplaySleep"] ?? 0) > 0
    }
}
