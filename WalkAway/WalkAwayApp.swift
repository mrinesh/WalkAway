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

class AppDelegate: NSObject, NSApplicationDelegate {
    // Main app components
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var timer: Timer? // Main timer until pre-break warning
    var finalCountdownTimer: Timer? // Timer for the 30s warning period
    var overlayWindowControllers: [OverlayWindowController] = []
    var notificationWindowController: NotificationWindowController? // Controller for the notification popup
    private var uiUpdateTimer: Timer?
    
    // Settings (persisted with UserDefaults)
    @AppStorage("breakFrequencyMinutes") var breakFrequencyMinutes: Int = 20
    @AppStorage("shortBreakDurationSeconds") var shortBreakDurationSeconds: Int = 20 // Renamed
    @AppStorage("longBreakDurationSeconds") var longBreakDurationSeconds: Int = 60  // Added
    @AppStorage("breakCycleCount") var breakCycleCount: Int = 0 // Added break counter
    @AppStorage("launchAtLoginEnabled") var launchAtLoginEnabled: Bool = false // Added for launch setting
    
    // Constants
    let preBreakWarningDuration: TimeInterval = 30.0 // Duration of the warning popup
    
    // Current state
    var isBreakActive = false
    var remainingSeconds = 0 // Remaining seconds *during* a break
    var isPreBreakWarningActive = false // Is the 30s warning active?
    
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
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("App launched. Setting up status bar.")
        
        // Set up status item in menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: "WalkAway")
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        // Set up popover with SwiftUI content
        popover = NSPopover()
        // Adjust size slightly to accommodate new control if necessary
        popover?.contentSize = NSSize(width: 300, height: 410) 
        popover?.behavior = .applicationDefined
        
        // Create the SwiftUI view for settings, passing new bindings
        let settingsView = SettingsView(
            frequencyMinutes: $breakFrequencyMinutes,
            shortBreakDurationSeconds: $shortBreakDurationSeconds, // Use renamed binding
            longBreakDurationSeconds: $longBreakDurationSeconds, // Pass new binding
            launchAtLoginEnabled: $launchAtLoginEnabled, // Pass launch setting binding
            isPaused: { [weak self] in self?.isPaused ?? false },
            timeUntilBreak: { [weak self] in self?.timeUntilBreakFormatted ?? "--:--" },
            onSettingsChanged: { [weak self] in
                self?.restartBreakTimer()
            },
            onPauseResumeToggled: { [weak self] in
                self?.togglePauseResume()
            },
            onLaunchSettingChanged: { [weak self] in // Add callback for launch setting
                self?.toggleLaunchAtLogin()
            }
        )
        
        // Wrap the SwiftUI view in a hosting controller
        let hostingController = NSHostingController(rootView: settingsView)
        popover?.contentViewController = hostingController
        
        // Sync launch at login status on startup
        syncLaunchAtLoginState()
        
        // Register for sleep/wake notifications
        setupSleepWakeNotifications()
        
        // Start the break timer
        startBreakTimer()
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
    
    func startBreakTimer() {
        invalidateAllTimers()
        isPaused = false
        isPreBreakWarningActive = false
        remainingPreBreakTime = 0
        
        let fullBreakInterval = TimeInterval(breakFrequencyMinutes * 60)
        let initialTimerInterval = max(0, fullBreakInterval - preBreakWarningDuration)
        remainingTimeUntilBreak = fullBreakInterval // Store the full duration for pause/resume
        
        print("Starting timer. Full interval: \(fullBreakInterval)s, Initial interval: \(initialTimerInterval)s")
        
        timerStartTime = Date()
        
        if initialTimerInterval <= 0 {
            // If frequency is <= 30s, trigger warning immediately
            print("Frequency <= warning duration, triggering warning immediately.")
            triggerPreBreakWarning()
        } else {
            // Start the main timer until the warning period
            timer = Timer(timeInterval: initialTimerInterval, repeats: false) { [weak self] _ in
                self?.triggerPreBreakWarning()
            }
            RunLoop.main.add(timer!, forMode: .common)
        }
        
        startUIUpdateTimer()
    }
    
    func restartBreakTimer() {
        guard !isBreakActive else { return }
        print("Restarting timer with new settings")
        startBreakTimer()
    }
    
    func triggerPreBreakWarning() {
        guard !isPaused, !isBreakActive else { return }
        
        timer?.invalidate() // Stop the main timer
        timer = nil
        
        isPreBreakWarningActive = true
        remainingTimeUntilBreak = preBreakWarningDuration // Update remaining time for display
        timerStartTime = Date() // Reset start time for the final countdown
        
        print("Triggering pre-break warning (\(preBreakWarningDuration)s remaining)")
        
        // Show Custom Notification instead of Alert
        showCustomNotification()
        
        // Start the final 30-second countdown timer
        finalCountdownTimer = Timer(timeInterval: preBreakWarningDuration, repeats: false) { [weak self] _ in
            self?.triggerBreak()
        }
        RunLoop.main.add(finalCountdownTimer!, forMode: .common)
        
        // Ensure UI updates during warning
        updateTimeDisplay()
    }
    
    // Replaces showPreBreakAlert
    func showCustomNotification() {
        // Close previous notification if any
        notificationWindowController?.closeNotificationImmediately()

        // Create and show new notification
        let notificationMessage = "Break starting in \(Int(preBreakWarningDuration))s..."
        notificationWindowController = NotificationWindowController(message: notificationMessage)
        notificationWindowController?.showNotification()
    }
    
    func triggerBreak() {
        guard !isBreakActive else { return }
        
        // Close notification window if it's still open
        notificationWindowController?.closeNotificationImmediately()
        notificationWindowController = nil

        finalCountdownTimer?.invalidate()
        finalCountdownTimer = nil
        isPreBreakWarningActive = false
        isBreakActive = true
        
        // Determine break duration (short/long)
        breakCycleCount += 1
        let isLongBreak = (breakCycleCount % 3 == 0)
        if isLongBreak {
            remainingSeconds = longBreakDurationSeconds
            print("Triggering LONG break (\(remainingSeconds)s)")
        } else {
            remainingSeconds = shortBreakDurationSeconds
            print("Triggering SHORT break (\(remainingSeconds)s)")
        }
        if breakCycleCount >= 99 { breakCycleCount = 0 }
        
        currentMessage = motivationalMessages.randomElement() ?? "Take a break!"
        
        // Create and show overlay windows
        overlayWindowControllers.forEach { $0.close() }
        overlayWindowControllers = []
        for screen in NSScreen.screens {
            let overlayController = OverlayWindowController(screen: screen)
            overlayController.currentMessage = currentMessage
            overlayController.skipCallback = { [weak self] in self?.finishBreak(skipped: true) }
            overlayController.showWindow(nil)
            overlayWindowControllers.append(overlayController)
        }
        
        startCountdownTimer()
    }
    
    // This timer runs DURING the break overlay
    func startCountdownTimer() {
        // Invalidate pre-break timers just in case
        timer?.invalidate()
        finalCountdownTimer?.invalidate()
        
        let countdownTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            self.remainingSeconds -= 1
            let formattedTime = self.formatTime(seconds: self.remainingSeconds)
            
            // Update time display on all overlay windows
            for overlayController in self.overlayWindowControllers {
                overlayController.updateTimeDisplay(formattedTime)
            }
            
            if self.remainingSeconds <= 0 {
                self.finishBreak(skipped: false)
            }
        }
        RunLoop.main.add(countdownTimer, forMode: .common)
        // Assign to main timer variable temporarily? No, need a separate one? 
        // Let's keep it simple: the break countdown doesn't use the main 'timer' or 'finalCountdownTimer'
        // We need to ensure finishBreak invalidates *this* timer if skipped.
        // Let's assign it to 'timer' as it represents the *active* timer during the break.
        self.timer = countdownTimer
    }
    
    func finishBreak(skipped: Bool) {
        invalidateAllTimers()
        isBreakActive = false
        isPreBreakWarningActive = false
        remainingPreBreakTime = 0
        
        // Close notification window if it's somehow still open
        notificationWindowController?.closeNotificationImmediately()
        notificationWindowController = nil

        overlayWindowControllers.forEach { $0.close() }
        overlayWindowControllers = []
        
        // Play sound
        if let soundURL = Bundle.main.url(forResource: "welcome", withExtension: "mp3") {
            NSSound(contentsOf: soundURL, byReference: false)?.play()
        } else {
            print("Warning: Custom sound file 'welcome.mp3' not found in bundle. Playing fallback.")
            NSSound(named: "Bottle")?.play()
        }
        
        startBreakTimer() // Restart the whole cycle
    }
    
    // Helper to invalidate all timers
    func invalidateAllTimers() {
        timer?.invalidate()
        finalCountdownTimer?.invalidate()
        uiUpdateTimer?.invalidate()
        timer = nil
        finalCountdownTimer = nil
        uiUpdateTimer = nil
    }
    
    func formatTime(seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
    
    func startUIUpdateTimer() {
        uiUpdateTimer?.invalidate()
        uiUpdateTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateTimeDisplay()
        }
        RunLoop.main.add(uiUpdateTimer!, forMode: .common)
        updateTimeDisplay()
    }
    
    func updateTimeDisplay() {
        if isBreakActive { return } // No update needed during break overlay itself
        
        if isPaused {
            // Show the correct stored remaining time when paused
            let remainingToDisplay = remainingPreBreakTime > 0 ? remainingPreBreakTime : remainingTimeUntilBreak
            timeUntilBreakFormatted = formatTime(seconds: Int(remainingToDisplay))
            return
        }
        
        var currentRemaining: TimeInterval = 0
        if let startTime = timerStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            if isPreBreakWarningActive {
                currentRemaining = max(0, preBreakWarningDuration - elapsed)
            } else {
                // Calculate remaining of the *full* interval until break
                let fullBreakInterval = TimeInterval(breakFrequencyMinutes * 60)
                currentRemaining = max(0, fullBreakInterval - elapsed)
            }
        } 
        // Store this for pause calculation if needed (only if not in warning phase)
        if !isPreBreakWarningActive {
            remainingTimeUntilBreak = currentRemaining
        }

        timeUntilBreakFormatted = formatTime(seconds: Int(currentRemaining))
    }
    
    func pauseTimer() {
        guard !isPaused && !isBreakActive else { return }
        
        let now = Date()
        if let startTime = timerStartTime {
            let elapsed = now.timeIntervalSince(startTime)
            
            if isPreBreakWarningActive {
                // Paused during final countdown
                remainingPreBreakTime = max(0, preBreakWarningDuration - elapsed)
                finalCountdownTimer?.invalidate()
                finalCountdownTimer = nil
                print("Timer paused during pre-break warning with \(formatTime(seconds: Int(remainingPreBreakTime))) remaining")
            } else {
                // Paused during main countdown
                let fullBreakInterval = TimeInterval(breakFrequencyMinutes * 60)
                remainingTimeUntilBreak = max(0, fullBreakInterval - elapsed)
                timer?.invalidate()
                timer = nil
                print("Timer paused with \(formatTime(seconds: Int(remainingTimeUntilBreak))) remaining until break")
            }
        }
        
        timerStartTime = nil // Clear start time
        isPaused = true
        updateTimeDisplay() // Update display to show paused time
    }
    
    func resumeTimer() {
        guard isPaused && !isBreakActive else { return }
        
        timerStartTime = Date() // Set new start time for resumed phase
        
        if remainingPreBreakTime > 0 {
            // Resuming final countdown
            print("Resuming pre-break warning timer with \(formatTime(seconds: Int(remainingPreBreakTime))) remaining")
            finalCountdownTimer = Timer(timeInterval: remainingPreBreakTime, repeats: false) { [weak self] _ in
                self?.triggerBreak()
            }
            RunLoop.main.add(finalCountdownTimer!, forMode: .common)
            isPreBreakWarningActive = true // Ensure flag is set
            remainingPreBreakTime = 0 // Clear stored value
        } else {
            // Resuming main countdown
            // Calculate time until warning needs to trigger
            let intervalUntilWarning = max(0, remainingTimeUntilBreak - preBreakWarningDuration)
            print("Resuming main timer with \(formatTime(seconds: Int(remainingTimeUntilBreak))) remaining until break (warning in \(formatTime(seconds: Int(intervalUntilWarning))))")
            
            if intervalUntilWarning <= 0 {
                // If remaining time is less than warning duration, trigger warning immediately
                triggerPreBreakWarning()
            } else {
                timer = Timer(timeInterval: intervalUntilWarning, repeats: false) { [weak self] _ in
                    self?.triggerPreBreakWarning()
                }
                RunLoop.main.add(timer!, forMode: .common)
            }
            isPreBreakWarningActive = false // Ensure flag is reset
        }
        
        isPaused = false
        updateTimeDisplay() // Update display immediately
    }
    
    func togglePauseResume() {
        if isPaused {
            resumeTimer()
        } else {
            pauseTimer()
        }
    }

    // MARK: - Sleep/Wake Handling
    func setupSleepWakeNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification, 
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc func systemWillSleep(_ notification: Notification) {
        print("System will sleep. Pausing timers.")
        // If a break is active, store remaining seconds
        if isBreakActive, let currentTimer = self.timer, currentTimer.isValid {
             // We don't have an easy way to get remaining time from a non-repeating timer like this.
             // Simplest is to just mark it paused. On wake, we'll finish the break.
             print("Sleeping during active break.")
             invalidateAllTimers() // Stop the break countdown
             isPaused = true // Mark as paused so wake logic knows
        } else if !isPaused { 
            // Pause timers only if not already paused manually
            pauseTimer() 
        }
    }

    @objc func systemDidWake(_ notification: Notification) {
        print("System did wake.")
        if isBreakActive && isPaused { // Woke up during an interrupted break
             print("Woke during break. Finishing break and restarting cycle.")
             finishBreak(skipped: true) // End the interrupted break
             // startBreakTimer() is called by finishBreak
        } else if isPaused { // Woke up during a normal paused state (main or pre-break)
            print("Resuming timer after wake.")
            resumeTimer()
        } else {
            // If not paused before sleep (shouldn't happen often, but maybe), ensure timers are running.
            print("Woke, wasn't paused. Ensuring timers are running.")
            // A simple restart might be safest if state is unexpected.
            restartBreakTimer()
        }
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
    
    // MARK: - Cleanup
    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self) // Remove observers
        invalidateAllTimers()
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Binding var frequencyMinutes: Int
    @Binding var shortBreakDurationSeconds: Int
    @Binding var longBreakDurationSeconds: Int
    @Binding var launchAtLoginEnabled: Bool
    
    var isPaused: () -> Bool
    var timeUntilBreak: () -> String
    var onSettingsChanged: () -> Void
    var onPauseResumeToggled: () -> Void
    var onLaunchSettingChanged: () -> Void

    // Local state for UI updates
    @State private var currentTime: String = "--:--"
    @State private var activeTrigger = false
    
    // State for the frequency slider
    @State private var frequencyValue: Double
    
    private let timerUpdatePublisher = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    // Initializer to set up the frequency slider state and accept new parameters
    init(frequencyMinutes: Binding<Int>, 
         shortBreakDurationSeconds: Binding<Int>,
         longBreakDurationSeconds: Binding<Int>,
         launchAtLoginEnabled: Binding<Bool>,
         isPaused: @escaping () -> Bool,
         timeUntilBreak: @escaping () -> String,
         onSettingsChanged: @escaping () -> Void,
         onPauseResumeToggled: @escaping () -> Void,
         onLaunchSettingChanged: @escaping () -> Void) {
        
        self._frequencyMinutes = frequencyMinutes
        self._shortBreakDurationSeconds = shortBreakDurationSeconds
        self._longBreakDurationSeconds = longBreakDurationSeconds
        self._launchAtLoginEnabled = launchAtLoginEnabled
        self.isPaused = isPaused
        self.timeUntilBreak = timeUntilBreak
        self.onSettingsChanged = onSettingsChanged
        self.onPauseResumeToggled = onPauseResumeToggled
        self.onLaunchSettingChanged = onLaunchSettingChanged
        
        // Initialize slider state from the binding
        self._frequencyValue = State(initialValue: Double(frequencyMinutes.wrappedValue))
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
                Text("Break Frequency: \(Int(frequencyValue)) minutes") // Display Int value
                    .font(.headline)
                Slider(value: $frequencyValue, in: 1...120, step: 1) {
                    // Empty label
                } minimumValueLabel: {
                    Text("1m").font(.caption)
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
            }
            .padding(.bottom, 10)

            // Duration Settings (Grouped Steppers)
            VStack(alignment: .leading, spacing: 10) {
                 Text("Break Durations")
                    .font(.headline)
                
                // Short Break Duration
                Stepper("Short Break: \(shortBreakDurationSeconds) seconds", value: $shortBreakDurationSeconds, in: 5...300, step: 15)
                    .onChange(of: shortBreakDurationSeconds) { _ in onSettingsChanged() }
                
                // Long Break Duration (Displaying and stepping in minutes, storing in seconds)
                Stepper("Long Break: \(longBreakDurationSeconds / 60) minutes", value: $longBreakDurationSeconds, in: 30...900, step: 60) // Step is 60 seconds (1 min)
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

            Divider()

            // Controls (Pause/Resume, Quit)
            HStack {
                Button(isPaused() ? "Resume Timer" : "Pause Timer") {
                    onPauseResumeToggled()
                }
                .controlSize(.regular)
                
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
