//
//  WalkAwayApp.swift
//  WalkAway
//
//  Created by rinesh on 04/04/25.
//

import SwiftUI
import AppKit
import Combine
import ServiceManagement // Import for Launch at Login
import AVFoundation
import CoreAudio
import AVKit // Add AVKit for capture device access
#if canImport(Darwin)
import Darwin
#endif

@main
struct WalkAwayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            // We need a real view here for the Settings window to work correctly.
            // SettingsView is shown in the popover, not here.
            SettingsPlaceholderView()
        }
    }
}

// Simple placeholder view for the main settings window (if needed)
struct SettingsPlaceholderView: View {
    var body: some View {
        Text("Configure WalkAway settings via the menu bar icon.")
            .padding()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    // Main app components
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var overlayWindowControllers: [OverlayWindowController] = []
    var notificationWindowController: NotificationWindowController? // Controller for the notification popup
    private var tickTimer: Timer? // Drives the work timer once per second
    private var breakCountdownTimer: Timer? // Counts down the break overlay
    private var meetingCheckTimer: Timer? // Added: Timer to check for active meetings
    
    // Settings (persisted with UserDefaults)
    @AppStorage("breakFrequencyMinutes") var breakFrequencyMinutes: Int = 30
    @AppStorage("shortBreakDurationSeconds") var shortBreakDurationSeconds: Int = 30
    @AppStorage("longBreakDurationSeconds") var longBreakDurationSeconds: Int = 300 // Changed to 5 minutes (300 seconds)
    @AppStorage("breakCycleCount") var breakCycleCount: Int = 0
    @AppStorage("launchAtLoginEnabled") var launchAtLoginEnabled: Bool = false // Added for launch setting
    @AppStorage("pauseForMeetingAppsEnabled") var pauseForMeetingAppsEnabled: Bool = false // Added missing binding
    @AppStorage("inactivityThresholdMinutes") var inactivityThresholdMinutes: Int = 10 // New setting
    
    // TEMP testing override: set to nil to use the user's configured frequency
    private let testingBreakFrequencyMinutes: Int? = nil
    private var effectiveBreakFrequencyMinutes: Int { testingBreakFrequencyMinutes ?? breakFrequencyMinutes }
    
    // Constants
    let preBreakWarningDuration: TimeInterval = 30.0 // Duration of the warning popup
    let targetMeetingAppBundleIDs: Set<String> = [
        "us.zoom.xos",             // Zoom
        "com.microsoft.teams",     // Microsoft Teams
        "com.webex.meetingmanager",// Webex Meetings App (may vary)
        "Cisco-Systems.Spark",    // Webex App (newer)
        "com.skype.skype",         // Skype
        // Browser-based are harder - might need to add Safari/Chrome/Edge if GMeet detection is critical, but it's less precise
        // "com.apple.Safari",
        // "com.google.Chrome",
        // "com.microsoft.edgemac"
    ]
    // Add missing declaration for ownBundleID
    let ownBundleID = Bundle.main.bundleIdentifier ?? "com.example.WalkAway" // Get own ID, provide fallback
    
    // Current state
    var isBreakActive = false
    var remainingSeconds = 0 // Remaining seconds *during* a break
    var pausedForMeetingApp: Bool = false // Added missing property declaration
    
    // Motivational messages
    let motivationalMessages = [
        "Stand up, stretch, take a walk. Your body will thank you and so will your mind!",
        "Hydrate! A quick glass of water will go a long way :)",
        "Look out the window, focus on something distant. Rest your eyes.",
        "Deep breaths. Relax your shoulders. Take a short walk around the room",
        "Time for a quick break! Step away and recharge."
    ]
    var currentMessage = ""
    
    // Pause state tracking
    var isPaused: Bool = false
    var timerStartTime: Date? // Start time of the current timer phase (main or final countdown)
    var remainingTimeUntilBreak: TimeInterval = 0 // Total time remaining until break starts (used when paused)
    var remainingPreBreakTime: TimeInterval = 0 // Time remaining in pre-break warning (used when paused)
    
    // Add a published property to update the UI with time remaining
    @objc dynamic var timeUntilBreakFormatted: String = "--:--"
    
    // Add properties for CPU tracking
    private var teamsCPUHistory: [Double] = []
    private let cpuHistoryMaxCount = 5 // 5 samples at 2-second intervals = 10 seconds
    private var lastCPUTime: (user: UInt64, system: UInt64)?
    private var lastCPUCheckTime: Date?
    
    // Work timer state (see BreakScheduler)
    private lazy var scheduler = BreakScheduler(configuration: currentSchedulerConfiguration())
    private var lastTickUptime = ProcessInfo.processInfo.systemUptime
    
    private enum ScreenOffReason {
        case screenSaver, screenLocked, displaysAsleep, systemAsleep, sessionInactive
    }
    // Saver and lock often overlap, so the screen only counts as back once every reason has cleared
    private var screenOffReasons: Set<ScreenOffReason> = []
    
    private func currentSchedulerConfiguration() -> BreakScheduler.Configuration {
        BreakScheduler.Configuration(
            workInterval: TimeInterval(effectiveBreakFrequencyMinutes * 60),
            awayThreshold: TimeInterval(inactivityThresholdMinutes * 60),
            warningLead: preBreakWarningDuration
        )
    }
    
    // MARK: - Meeting Detection Protocol and Types
    protocol MeetingDetector {
        func isInMeeting() -> Bool
        var name: String { get }
    }

    // MARK: - Zoom Meeting Detector
    class ZoomMeetingDetector: MeetingDetector {
        var name: String { "Zoom" }
        
        func isInMeeting() -> Bool {
            ProcessInfo.processInfo.processIdentifier != 0 &&
                NSRunningApplication.runningApplications(withBundleIdentifier: "us.zoom.CptHost").count > 0
        }
    }

    // MARK: - Webex Meeting Detector
    class WebexMeetingDetector: MeetingDetector {
        var name: String { "Webex" }
        
        func isInMeeting() -> Bool {
            NSWorkspace.shared.runningApplications.contains { app in
                if let executableName = app.executableURL?.lastPathComponent {
                    return executableName.lowercased() == "washost"
                }
                return false
            }
        }
    }

    // MARK: - Teams Meeting Detector
    class TeamsMeetingDetector: MeetingDetector {
        var name: String { "Teams" }
        private var cpuHistory: [Double] = []
        private let cpuHistoryMaxCount = 5
        private var lastCPUTime: (user: UInt64, system: UInt64)?
        private var lastCPUCheckTime: Date?
        
        func isInMeeting() -> Bool {
            // First check if Teams is running
            guard let teamsApp = NSWorkspace.shared.runningApplications.first(where: { $0.executableURL?.lastPathComponent == "MSTeams" }) else {
                cpuHistory.removeAll()
                lastCPUTime = nil
                lastCPUCheckTime = nil
                return false
            }
            
            // Get CPU usage
            let pid = teamsApp.processIdentifier
            var info = proc_taskinfo()
            let size = MemoryLayout<proc_taskinfo>.size
            let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(size))
            
            if result <= 0 {
                print("[Meeting Check] Error getting Teams process info: \(result)")
                return false
            }
            
            let now = Date()
            let currentCPUTime = (user: info.pti_total_user, system: info.pti_total_system)
            
            // Calculate CPU usage percentage
            var cpuUsage: Double = 0.0
            if let lastTime = lastCPUTime, let lastCheck = lastCPUCheckTime {
                let timeDiff = now.timeIntervalSince(lastCheck)
                let userDiff = Double(currentCPUTime.user - lastTime.user)
                let systemDiff = Double(currentCPUTime.system - lastTime.system)
                
                cpuUsage = ((userDiff + systemDiff) / (timeDiff * 10_000_000.0)) * 100.0
                
                cpuHistory.append(cpuUsage)
                if cpuHistory.count > cpuHistoryMaxCount {
                    cpuHistory.removeFirst()
                }
            }
            
            lastCPUTime = currentCPUTime
            lastCPUCheckTime = now
            
            let averageCPU = cpuHistory.isEmpty ? 0.0 : cpuHistory.reduce(0.0, +) / Double(cpuHistory.count)
            return averageCPU > 10.0
        }
    }

    // MARK: - Meeting Monitor
    class MeetingMonitor {
        private let detectors: [MeetingDetector]
        
        init() {
            self.detectors = [
                ZoomMeetingDetector(),
                WebexMeetingDetector(),
                TeamsMeetingDetector()
            ]
        }
        
        func checkForActiveMeetings() -> (isActive: Bool, activeMeetingApp: String?) {
            for detector in detectors {
                if detector.isInMeeting() {
                    print("[Meeting Check] \(detector.name) meeting detected")
                    return (true, detector.name)
                }
            }
            return (false, nil)
        }
    }

    // Add MeetingMonitor property to AppDelegate
    private var meetingMonitor: MeetingMonitor!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Use self.ownBundleID to resolve scope
        print("App launched. Own bundle ID: \(self.ownBundleID)") 
        
        // Set up status item in menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        // Add workspace notification observer for app switching
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppActivation(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "figure.walk", accessibilityDescription: "WalkAway")
            // Restore direct action to open popover on click
            button.action = #selector(togglePopover)
            button.target = self 
        }
        
        // Set up popover with SwiftUI content
        popover = NSPopover()
        // Adjust size slightly to accommodate new control if necessary
        popover?.contentSize = NSSize(width: 300, height: 510) 
        popover?.behavior = .applicationDefined
        
        // Create the SwiftUI view for settings, passing new bindings
        let settingsView = SettingsView(
            frequencyMinutes: $breakFrequencyMinutes,
            shortBreakDurationSeconds: $shortBreakDurationSeconds,
            longBreakDurationSeconds: $longBreakDurationSeconds,
            launchAtLoginEnabled: $launchAtLoginEnabled,
            pauseForMeetingAppsEnabled: $pauseForMeetingAppsEnabled,
            inactivityThresholdMinutes: $inactivityThresholdMinutes,
            isPaused: { [weak self] in self?.isPaused ?? false },
            isPausedForMeeting: { [weak self] in self?.pausedForMeetingApp ?? false },
            timeUntilBreak: { [weak self] in self?.timeUntilBreakFormatted ?? "--:--" },
            onSettingsChanged: { [weak self] in
                self?.restartBreakTimer()
            },
            onPauseResumeToggled: { [weak self] in
                self?.togglePauseResume()
            },
            onLaunchSettingChanged: { [weak self] in
                self?.toggleLaunchAtLogin()
            }
        )
        
        // Wrap the SwiftUI view in a hosting controller
        let hostingController = NSHostingController(rootView: settingsView)
        popover?.contentViewController = hostingController
        
        // Sync launch at login status on startup
        syncLaunchAtLoginState()
        
        setupScreenStateObservers()
        
        meetingMonitor = MeetingMonitor()
        startMeetingCheckTimer()
        
        startTickTimer()
    }
    
    @objc func togglePopover() {
        if let popover = popover, let button = statusItem?.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
                
                // Add this line to ensure the time display is updated immediately when opening the popover
                updateTimeDisplay()
            }
        }
    }
    
    // MARK: - Work Timer

    private func startTickTimer() {
        lastTickUptime = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
        updateTimeDisplay()
    }

    private func tick() {
        let uptime = ProcessInfo.processInfo.systemUptime
        let elapsed = uptime - lastTickUptime
        lastTickUptime = uptime

        // Re-read settings every tick so slider changes apply immediately
        scheduler.configuration = currentSchedulerConfiguration()
        let inputs = BreakScheduler.Inputs(
            idleSeconds: SystemActivity.secondsSinceLastInput(),
            isVideoPlaying: SystemActivity.isDisplaySleepPrevented(),
            isInMeeting: pausedForMeetingApp,
            isManuallyPaused: isPaused && !pausedForMeetingApp
        )
        handle(scheduler.tick(elapsed: elapsed, now: Date().timeIntervalSinceReferenceDate, inputs: inputs))
        updateTimeDisplay()
    }

    private func handle(_ events: [BreakScheduler.Event]) {
        for event in events {
            switch event {
            case .warning:
                showCustomNotification()
            case .breakDue:
                triggerBreak()
            case .wentAway:
                print("[Activity] User is away. Break cycle reset.")
                breakCycleCount = 0
                notificationWindowController?.closeNotificationImmediately()
                notificationWindowController = nil
                if isBreakActive {
                    closeBreakOverlay()
                }
            case .returned:
                print("[Activity] User is back. Timer resumed.")
            }
        }
    }

    func restartBreakTimer() {
        guard !isBreakActive else { return }
        print("Restarting timer with new settings")
        scheduler.configuration = currentSchedulerConfiguration()
        scheduler.resetCycle()
        updateTimeDisplay()
    }

    func showCustomNotification() {
        notificationWindowController?.closeNotificationImmediately()
        let secondsLeft = Int(scheduler.remaining.rounded(.up))
        notificationWindowController = NotificationWindowController(message: "Break starting in \(secondsLeft)s...")
        notificationWindowController?.showNotification()
    }

    // MARK: - Break Overlay

    func triggerBreak() {
        guard !isBreakActive else { return }

        notificationWindowController?.closeNotificationImmediately()
        notificationWindowController = nil
        isBreakActive = true

        // Pause any playing media so it doesn't keep running in the background during the break
        MediaController.shared.pauseIfPlaying()

        // Every 3rd break is a long, non-skippable one
        breakCycleCount += 1
        let isLongBreak = (breakCycleCount % 3 == 0)
        remainingSeconds = isLongBreak ? longBreakDurationSeconds : shortBreakDurationSeconds
        print("Triggering \(isLongBreak ? "LONG (non-skippable)" : "SHORT (skippable)") break (\(remainingSeconds)s)")
        if breakCycleCount >= 99 { breakCycleCount = 0 }

        currentMessage = motivationalMessages.randomElement() ?? "Take a break!"

        overlayWindowControllers.forEach { $0.close() }
        overlayWindowControllers = []
        for screen in NSScreen.screens {
            let overlayController = OverlayWindowController(screen: screen, isSkippable: !isLongBreak)
            overlayController.currentMessage = currentMessage
            overlayController.skipCallback = { [weak self] in
                self?.finishBreak(skipped: true)
            }
            overlayController.showWindow(nil)
            overlayWindowControllers.append(overlayController)
        }

        startCountdownTimer()
    }

    func startCountdownTimer() {
        breakCountdownTimer?.invalidate()
        let countdownTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            self.remainingSeconds -= 1
            let formattedTime = self.formatTime(seconds: self.remainingSeconds)
            for overlayController in self.overlayWindowControllers {
                overlayController.updateTimeDisplay(formattedTime)
            }

            if self.remainingSeconds <= 0 {
                self.finishBreak(skipped: false)
            }
        }
        RunLoop.main.add(countdownTimer, forMode: .common)
        breakCountdownTimer = countdownTimer
    }

    func finishBreak(skipped: Bool) {
        closeBreakOverlay()

        if let soundURL = Bundle.main.url(forResource: "welcome", withExtension: "mp3") {
            NSSound(contentsOf: soundURL, byReference: false)?.play()
        } else {
            print("Warning: Custom sound file 'welcome.mp3' not found in bundle. Playing fallback.")
            NSSound(named: "Bottle")?.play()
        }

        scheduler.finishBreak()
        updateTimeDisplay()
    }

    private func closeBreakOverlay() {
        breakCountdownTimer?.invalidate()
        breakCountdownTimer = nil
        isBreakActive = false
        notificationWindowController?.closeNotificationImmediately()
        notificationWindowController = nil
        overlayWindowControllers.forEach { $0.close() }
        overlayWindowControllers = []
    }

    func formatTime(seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    func updateTimeDisplay() {
        if isBreakActive { return }
        if scheduler.phase == .away && !isPaused {
            timeUntilBreakFormatted = "Away"
        } else {
            timeUntilBreakFormatted = formatTime(seconds: Int(scheduler.remaining.rounded(.up)))
        }
    }

    // MARK: - Pause / Resume

    func pauseTimer(isMeetingPause: Bool = false) {
        guard !isPaused && !isBreakActive else { return }
        isPaused = true
        pausedForMeetingApp = isMeetingPause
        if isMeetingPause {
            showPauseNotification(message: "Timer paused for Meeting App")
        }
        updateTimeDisplay()
    }

    func resumeTimer() {
        guard isPaused && !isBreakActive else { return }
        isPaused = false
        pausedForMeetingApp = false
        updateTimeDisplay()
    }

    func togglePauseResume() {
        if isPaused {
            resumeTimer()
        } else {
            pauseTimer()
        }
        self.objectWillChange.send()
    }

    func showPauseNotification(message: String) {
        notificationWindowController?.closeNotificationImmediately()
        notificationWindowController = NotificationWindowController(message: message)
        notificationWindowController?.showNotification()
    }

    // MARK: - Screen State (saver, lock, display sleep, system sleep, user switching)

    private var screenObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    private func setupScreenStateObservers() {
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        let observations: [(NotificationCenter, Notification.Name, ScreenOffReason, Bool)] = [
            (distributed, Notification.Name("com.apple.screensaver.didstart"), .screenSaver, true),
            (distributed, Notification.Name("com.apple.screensaver.didstop"), .screenSaver, false),
            (distributed, Notification.Name("com.apple.screenIsLocked"), .screenLocked, true),
            (distributed, Notification.Name("com.apple.screenIsUnlocked"), .screenLocked, false),
            (workspace, NSWorkspace.screensDidSleepNotification, .displaysAsleep, true),
            (workspace, NSWorkspace.screensDidWakeNotification, .displaysAsleep, false),
            (workspace, NSWorkspace.willSleepNotification, .systemAsleep, true),
            (workspace, NSWorkspace.didWakeNotification, .systemAsleep, false),
            (workspace, NSWorkspace.sessionDidResignActiveNotification, .sessionInactive, true),
            (workspace, NSWorkspace.sessionDidBecomeActiveNotification, .sessionInactive, false),
        ]
        for (center, name, reason, isOff) in observations {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.setScreenOff(isOff, reason: reason)
            }
            screenObservers.append((center, token))
        }
    }

    private func setScreenOff(_ isOff: Bool, reason: ScreenOffReason) {
        let now = Date().timeIntervalSinceReferenceDate
        let wasOff = !screenOffReasons.isEmpty
        if isOff {
            screenOffReasons.insert(reason)
        } else {
            screenOffReasons.remove(reason)
        }
        let isNowOff = !screenOffReasons.isEmpty

        if isNowOff && !wasOff {
            print("[Screen] Off (\(reason))")
            scheduler.screenDidTurnOff(at: now)
        } else if !isNowOff && wasOff {
            print("[Screen] On")
            handle(scheduler.screenDidTurnOn(at: now))
        }
        updateTimeDisplay()
    }

    // MARK: - Launch at Login
    func syncLaunchAtLoginState() {
        // Ensure the system state matches the stored preference on launch
        toggleLaunchAtLogin()
    }
    
    func toggleLaunchAtLogin() {
        print("Setting Launch at Login to: \(launchAtLoginEnabled)")
        do {
            if launchAtLoginEnabled {
                if SMAppService.mainApp.status == .notRegistered {
                    try SMAppService.mainApp.register()
                    print("Successfully registered app for launch at login.")
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                    print("Successfully unregistered app from launch at login.")
                }
            }
        } catch {
            print("Failed to update Launch at Login setting: \(error.localizedDescription)")
            // Optionally revert the toggle state if setting failed
            // launchAtLoginEnabled.toggle()
        }
    }
    
    // MARK: - Meeting App Handling & Activation
    @objc func handleAppActivation(_ notification: Notification) {
        guard pauseForMeetingAppsEnabled else { return } // Only act if feature is enabled
        
        guard let activatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = activatedApp.bundleIdentifier else { return }
              
        // Check specifically for Zoom activation
        if bundleID == "us.zoom.xos" {
            // Check if timer is actively running
            if !isPaused && !isBreakActive {
                
                // Get all windows
                let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
                guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[CFString: Any]] else { return }
                
                // Look specifically for Zoom meeting windows
                var zoomMeetingActive = false
                let zoomPID = activatedApp.processIdentifier
                
                print("Checking Zoom windows for PID: \(zoomPID)")
                
                for windowDict in windowList {
                    guard let ownerPID = windowDict[kCGWindowOwnerPID] as? pid_t,
                          ownerPID == zoomPID,
                          let isOnscreen = windowDict[kCGWindowIsOnscreen] as? Bool,
                          isOnscreen,
                          let alpha = windowDict[kCGWindowAlpha] as? Double,
                          alpha > 0 else { continue }
                    
                    // Debug: Print window names to help identify patterns
                    if let name = windowDict[kCGWindowName] as? String {
                        print("Found Zoom window: '\(name)'")
                    }
                    
                    // Check for any window name that indicates an active meeting
                    if let windowName = windowDict[kCGWindowName] as? String {
                        // Common Zoom meeting window patterns
                        let meetingPatterns = [
                            "Zoom Meeting",
                            "zoom share",
                            "Zoom Webinar",
                            "Zoom Video",
                            "Meeting Controls",
                            "Zoom Group Chat",
                            "Participants",
                            "Chat",
                            "Share Screen",
                            "Audio Conference"
                        ]
                        
                        // Check if window name contains any of our patterns
                        if meetingPatterns.contains(where: { windowName.contains($0) }) ||
                           // Also check for common meeting UI elements
                           (windowName.contains("Zoom") && 
                            (windowName.contains("Controls") || 
                             windowName.contains("Participants") || 
                             windowName.contains("Share"))) {
                            print("Detected active meeting window: '\(windowName)'")
                            zoomMeetingActive = true
                            break
                        }
                    }
                }

                if zoomMeetingActive {
                    print("Zoom meeting detected. Pausing timer.")
                    pauseTimer(isMeetingPause: true)
                } else {
                    print("Zoom is open but no active meeting detected. Timer continues.")
                    // If timer was paused for a meeting and meeting ended, resume
                    if isPaused && pausedForMeetingApp {
                        resumeTimer()
                    }
                }
            }
        } else if bundleID == ownBundleID { 
            // WalkAway itself became active
            if isPaused && pausedForMeetingApp {
                // Check if Zoom still has an active meeting before resuming
                if let zoomApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "us.zoom.xos" }) {
                    let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
                    if let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[CFString: Any]] {
                        var meetingStillActive = false
                        let zoomPID = zoomApp.processIdentifier
                        
                        for windowDict in windowList {
                            if let ownerPID = windowDict[kCGWindowOwnerPID] as? pid_t,
                               ownerPID == zoomPID,
                               let windowName = windowDict[kCGWindowName] as? String,
                               let isOnscreen = windowDict[kCGWindowIsOnscreen] as? Bool,
                               isOnscreen,
                               (windowName.contains("Zoom Meeting") || 
                                windowName.contains("zoom share") ||
                                windowName.contains("zoom share statusbar window")) {
                                meetingStillActive = true
                                break
                            }
                        }
                        
                        if !meetingStillActive {
                            print("WalkAway activated and no active Zoom meeting detected. Resuming timer.")
                            resumeTimer()
                        }
                    }
                } else {
                    // Zoom is not running anymore, safe to resume
                    print("WalkAway activated and Zoom not running. Resuming timer.")
                    resumeTimer()
                }
            }
        }
        // Note: Logic for other meeting apps (Teams, etc.) is currently removed based on the request
        // To re-add, you would replicate the Zoom check structure for their bundle IDs.
    }
    
    // MARK: - Cleanup
    deinit {
        screenObservers.forEach { $0.center.removeObserver($0.token) }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        tickTimer?.invalidate()
        breakCountdownTimer?.invalidate()
        meetingCheckTimer?.invalidate()
    }

    func startMeetingCheckTimer() {
        meetingCheckTimer?.invalidate()
        meetingCheckTimer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkForActiveMeetings()
        }
        if let timer = meetingCheckTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func checkForActiveMeetings() {
        guard pauseForMeetingAppsEnabled,
              !isBreakActive else {
            return
        }

        let meetingStatus = meetingMonitor.checkForActiveMeetings()

        if meetingStatus.isActive && !isPaused {
            print("[Meeting Check] \(meetingStatus.activeMeetingApp ?? "Unknown") meeting detected. Pausing timer.")
            pauseTimer(isMeetingPause: true)
        } else if !meetingStatus.isActive && isPaused && pausedForMeetingApp {
            print("[Meeting Check] No active meetings detected. Resuming timer.")
            resumeTimer()
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Binding var frequencyMinutes: Int
    @Binding var shortBreakDurationSeconds: Int
    @Binding var longBreakDurationSeconds: Int
    @Binding var launchAtLoginEnabled: Bool
    @Binding var pauseForMeetingAppsEnabled: Bool
    @Binding var inactivityThresholdMinutes: Int
    
    var isPaused: () -> Bool
    var isPausedForMeeting: () -> Bool
    var timeUntilBreak: () -> String
    var onSettingsChanged: () -> Void
    var onPauseResumeToggled: () -> Void
    var onLaunchSettingChanged: () -> Void

    // Local state for UI updates
    @State private var currentTime: String = "--:--"
    @State private var activeTrigger = false
    
    // State for the frequency slider
    @State private var frequencyValue: Double
    
    // Add state for inactivity slider
    @State private var inactivityValue: Double
    
    private let timerUpdatePublisher = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    // Initializer to set up the frequency slider state and accept new parameters
    init(frequencyMinutes: Binding<Int>, 
         shortBreakDurationSeconds: Binding<Int>,
         longBreakDurationSeconds: Binding<Int>,
         launchAtLoginEnabled: Binding<Bool>,
         pauseForMeetingAppsEnabled: Binding<Bool>,
         inactivityThresholdMinutes: Binding<Int>,
         isPaused: @escaping () -> Bool,
         isPausedForMeeting: @escaping () -> Bool,
         timeUntilBreak: @escaping () -> String,
         onSettingsChanged: @escaping () -> Void,
         onPauseResumeToggled: @escaping () -> Void,
         onLaunchSettingChanged: @escaping () -> Void) {
        
        self._frequencyMinutes = frequencyMinutes
        self._shortBreakDurationSeconds = shortBreakDurationSeconds
        self._longBreakDurationSeconds = longBreakDurationSeconds
        self._launchAtLoginEnabled = launchAtLoginEnabled
        self._pauseForMeetingAppsEnabled = pauseForMeetingAppsEnabled
        self._inactivityThresholdMinutes = inactivityThresholdMinutes
        self.isPaused = isPaused
        self.isPausedForMeeting = isPausedForMeeting
        self.timeUntilBreak = timeUntilBreak
        self.onSettingsChanged = onSettingsChanged
        self.onPauseResumeToggled = onPauseResumeToggled
        self.onLaunchSettingChanged = onLaunchSettingChanged
        
        // Initialize slider states
        self._frequencyValue = State(initialValue: Double(frequencyMinutes.wrappedValue))
        self._inactivityValue = State(initialValue: Double(inactivityThresholdMinutes.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { 
            Text("WalkAway Settings")
                .font(.title3) 
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 5)

            Divider()
            
            // Time Until Next Break Display
            HStack {
                Text("Next Break In:")
                    .font(.headline)
                Spacer()
                Text(currentTime)
                    .font(.system(.title2, design: .monospaced).weight(.medium))
                    .id("timeDisplay_\(activeTrigger)") // Use trigger for refresh
            }
            .padding(.vertical, 5)
            
            Divider()
            
            // Frequency Setting using Slider
            VStack(alignment: .leading, spacing: 5) {
                Text("Break Frequency: \(Int(frequencyValue)) minutes")
                    .font(.headline)
                Slider(value: $frequencyValue, in: 30...120, step: 10) {
                    // Empty label
                } minimumValueLabel: {
                    Text("30m").font(.caption)
                } maximumValueLabel: {
                    Text("120m").font(.caption)
                }
                .onChange(of: frequencyValue) { newValue in
                    let newIntValue = Int(newValue)
                    // Update binding only if the integer value actually changed
                    if newIntValue != frequencyMinutes {
                        frequencyMinutes = newIntValue
                        onSettingsChanged() 
                    }
                }
                // Ensure slider state reflects external changes if needed (e.g., from AppStorage defaults)
                .onAppear {
                   frequencyValue = Double(frequencyMinutes) 
                }
                Text("Break reminder every \(Int(frequencyValue)) minutes")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.bottom, 10)

            // Replace Inactivity Threshold Stepper with Slider
            VStack(alignment: .leading, spacing: 5) {
                Text("Reset after inactive for: \(Int(inactivityValue)) minutes")
                    .font(.headline)
                Slider(value: $inactivityValue, in: 5...60, step: 5) {
                    // Empty label
                } minimumValueLabel: {
                    Text("5m").font(.caption)
                } maximumValueLabel: {
                    Text("60m").font(.caption)
                }
                .onChange(of: inactivityValue) { newValue in
                    let newIntValue = Int(newValue)
                    // Update binding only if the integer value actually changed
                    if newIntValue != inactivityThresholdMinutes {
                        inactivityThresholdMinutes = newIntValue
                    }
                }
                // Ensure slider state reflects external changes
                .onAppear {
                    inactivityValue = Double(inactivityThresholdMinutes)
                }
                Text("Timer will reset after this period of inactivity")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.bottom, 10)

            // Duration Settings (Grouped Steppers)
            VStack(alignment: .leading, spacing: 10) {
                 Text("Break Durations")
                    .font(.headline)
                
                // Short Break Duration
                Stepper("Short Break: \(shortBreakDurationSeconds) seconds", value: $shortBreakDurationSeconds, in: 30...180, step: 30)
                    .onChange(of: shortBreakDurationSeconds) { _ in onSettingsChanged() }
                
                // Long Break Duration (Displaying and stepping in minutes, storing in seconds)
                Stepper("Long Break: \(longBreakDurationSeconds / 60) minutes", value: $longBreakDurationSeconds, in: 300...1800, step: 300) // 5-30 minutes in steps of 5
                    .onChange(of: longBreakDurationSeconds) { _ in onSettingsChanged() }
                Text("(Every 3rd break)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.bottom, 10)

            // Launch At Login Setting
            Toggle("Launch at Login", isOn: $launchAtLoginEnabled)
                .onChange(of: launchAtLoginEnabled) { _ in 
                    onLaunchSettingChanged()
                }
                .padding(.bottom, 10)

            // Meeting App Pause Setting (Adding missing Toggle)
            Toggle("Pause for Meeting Apps", isOn: $pauseForMeetingAppsEnabled)
                // No onChange needed here as AppDelegate reads @AppStorage directly
                .padding(.bottom, 10)

            Divider()

            // Controls (Pause/Resume, Quit)
            HStack {
                Button(isPaused() ? "Resume Timer" : "Pause Timer") {
                    onPauseResumeToggled()
                }
                .controlSize(.regular)
                .disabled(isPaused() && isPausedForMeeting()) // Added missing disabled modifier
                
                Spacer()
                
                Button("Quit WalkAway") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
                .controlSize(.regular) 
            }
        }
        .padding(12) 
        .onReceive(timerUpdatePublisher) { _ in
            let newTime = timeUntilBreak()
            if newTime != currentTime {
                currentTime = newTime
                activeTrigger.toggle() // Force refresh if needed
            }
        }
        .onAppear {
            // Set initial time immediately
            currentTime = timeUntilBreak()
            // Ensure slider reflects current setting on appear
            frequencyValue = Double(frequencyMinutes)
        }
    }
}

// MARK: - Notification Window Components (Added Here)

class NotificationWindowController: NSWindowController, NSWindowDelegate {

    private var autoCloseTimer: Timer?
    private let displayDuration: TimeInterval = 5.0 // How long the notification stays visible

    // Convenience initializer
    convenience init(message: String) {
        // Create a small, borderless window
        let windowSize = NSSize(width: 280, height: 60)
        // Position calculation will happen in showNotification
        let initialRect = NSRect(origin: .zero, size: windowSize) 

        let window = NSWindow(
            contentRect: initialRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // Configure window properties
        window.level = .floating // Keep it above most other windows
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.ignoresMouseEvents = true // Notification is not interactive
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle] // Behaves like a temporary panel

        // Use SwiftUI for the content view
        let notificationView = NotificationView(message: message)
        let hostingController = NSHostingController(rootView: notificationView)
        hostingController.view.frame.size = windowSize
        window.contentViewController = hostingController

        self.init(window: window)
        window.delegate = self // Set delegate for potential future use
    }

    // Show the notification window positioned and start auto-close timer
    func showNotification() {
        guard let window = self.window else { return }
        
        // Calculate position (e.g., top-right corner of main screen)
        if let mainScreen = NSScreen.main {
            let screenRect = mainScreen.visibleFrame // Use visibleFrame to avoid menu/dock
            let padding: CGFloat = 20
            let windowSize = window.frame.size
            let originX = screenRect.maxX - windowSize.width - padding
            let originY = screenRect.maxY - windowSize.height - padding
            window.setFrameOrigin(NSPoint(x: originX, y: originY))
        }

        // Fade in animation
        window.alphaValue = 0
        window.orderFrontRegardless() // Show without activating app
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            window.animator().alphaValue = 1.0
        })

        // Start timer to auto-close
        autoCloseTimer?.invalidate() // Invalidate previous timer if any
        autoCloseTimer = Timer.scheduledTimer(
            timeInterval: displayDuration,
            target: self,
            selector: #selector(closeNotificationAnimated),
            userInfo: nil,
            repeats: false
        )
        // Ensure timer runs even if UI is busy
        if let timer = autoCloseTimer {
             RunLoop.main.add(timer, forMode: .common)
        }
    }

    // Close the notification window immediately
    func closeNotificationImmediately() {
        autoCloseTimer?.invalidate()
        autoCloseTimer = nil
        // Check if window exists and is visible before closing
        if self.window?.isVisible ?? false {
             self.close() // NSWindowController's close method
        }
    }
    
    // Close the notification window with fade-out animation (called by timer)
    @objc private func closeNotificationAnimated() {
         guard let window = self.window, window.isVisible else {
             closeNotificationImmediately() // Close immediately if not visible or no window
             return
         }

        autoCloseTimer?.invalidate()
        autoCloseTimer = nil
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            window.animator().alphaValue = 0
        }, completionHandler: {
            self.close() // Call NSWindowController's close
        })
    }

    // Ensure timer is invalidated if the window controller is deallocated
    deinit {
        print("NotificationWindowController deinit")
        autoCloseTimer?.invalidate()
    }
}

// Simple SwiftUI view for the notification content
struct NotificationView: View {
    let message: String

    var body: some View {
        ZStack {
             // Background with blur effect
             VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                 .cornerRadius(10) // Rounded corners

             // Message Text
             Text(message)
                 .font(.system(size: 14, weight: .medium))
                 .foregroundColor(.primary.opacity(0.9))
                 .padding(.horizontal, 15)
                 .padding(.vertical, 10)
                 .multilineTextAlignment(.center)
         }
         .frame(maxWidth: .infinity, maxHeight: .infinity)
         .edgesIgnoringSafeArea(.all) // Allow background to fill corners
    }
}

// Helper view for NSVisualEffectView in SwiftUI
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

