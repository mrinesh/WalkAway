//
//  WalkAwayApp.swift
//  WalkAway
//
//  Created by rinesh on 04/04/25.
//

import SwiftUI
import AppKit
import Combine

@main
struct WalkAwayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    // Main app components
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var timer: Timer?
    var overlayWindowController: OverlayWindowController?
    private var uiUpdateTimer: Timer?
    
    // Settings (persisted with UserDefaults)
    @AppStorage("breakFrequencyMinutes") var breakFrequencyMinutes: Int = 20
    @AppStorage("breakDurationSeconds") var breakDurationSeconds: Int = 20
    
    // Current state
    var isBreakActive = false
    var remainingSeconds = 0
    
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
    var timerStartTime: Date?
    var remainingTimeUntilBreak: TimeInterval = 0
    
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
        popover?.contentSize = NSSize(width: 300, height: 380)
        popover?.behavior = .applicationDefined
        
        // Create the SwiftUI view for settings
        let settingsView = SettingsView(
            frequencyMinutes: $breakFrequencyMinutes,
            durationSeconds: $breakDurationSeconds,
            isPaused: { [weak self] in self?.isPaused ?? false },
            timeUntilBreak: { [weak self] in self?.timeUntilBreakFormatted ?? "--:--" },
            onSettingsChanged: { [weak self] in
                self?.restartBreakTimer()
            },
            onPauseResumeToggled: { [weak self] in
                self?.togglePauseResume()
            }
        )
        
        // Wrap the SwiftUI view in a hosting controller
        let hostingController = NSHostingController(rootView: settingsView)
        popover?.contentViewController = hostingController
        
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
        timer?.invalidate()
        
        let breakInterval = TimeInterval(breakFrequencyMinutes * 60)
        print("Starting timer for \(breakFrequencyMinutes) minutes")
        
        // Reset pause state
        isPaused = false
        
        // Store the start time
        timerStartTime = Date()
        remainingTimeUntilBreak = breakInterval
        
        // Start a timer that will fire the break
        let mainTimer = Timer(timeInterval: breakInterval, repeats: false) { [weak self] _ in
            self?.triggerBreak()
        }
        // Add to common mode to ensure it runs during interface events
        RunLoop.main.add(mainTimer, forMode: .common)
        self.timer = mainTimer
        
        // Start a UI update timer to keep the time remaining display fresh
        startUIUpdateTimer()
    }
    
    func restartBreakTimer() {
        guard !isBreakActive else { return }
        
        print("Restarting timer with new settings")
        startBreakTimer()
    }
    
    func triggerBreak() {
        guard !isBreakActive else { return }
        
        isBreakActive = true
        remainingSeconds = breakDurationSeconds
        currentMessage = motivationalMessages.randomElement() ?? "Take a break!"
        
        // Create overlay window
        overlayWindowController = OverlayWindowController()
        overlayWindowController?.currentMessage = currentMessage
        overlayWindowController?.skipCallback = { [weak self] in
            self?.finishBreak(skipped: true)
        }
        overlayWindowController?.showWindow(nil)
        
        // Start countdown timer
        startCountdownTimer()
    }
    
    func startCountdownTimer() {
        timer?.invalidate()
        
        // Create a timer that runs even during UI interactions
        let countdownTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            self.remainingSeconds -= 1
            let formattedTime = self.formatTime(seconds: self.remainingSeconds)
            self.overlayWindowController?.updateTimeDisplay(formattedTime)
            
            if self.remainingSeconds <= 0 {
                self.finishBreak(skipped: false)
            }
        }
        // Add to run loop in common mode
        RunLoop.main.add(countdownTimer, forMode: .common)
        self.timer = countdownTimer
    }
    
    func finishBreak(skipped: Bool) {
        isBreakActive = false
        timer?.invalidate()
        
        overlayWindowController?.close()
        overlayWindowController = nil
        
        // Play a sound to indicate the break is over
        NSSound(named: "Glass")?.play()
        
        // Restart the main timer
        startBreakTimer()
    }
    
    func formatTime(seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
    
    // Add a new method to start a UI update timer
    func startUIUpdateTimer() {
        uiUpdateTimer?.invalidate()
        
        // Create a timer that continues running even during tracking (like when a menu is open)
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateTimeDisplay()
        }
        
        // Add to RunLoop in a mode that continues during UI interaction
        RunLoop.main.add(timer, forMode: .common)
        
        // Store reference
        uiUpdateTimer = timer
        
        // Update immediately to show current time
        updateTimeDisplay()
    }
    
    // Add a method to update the time display
    func updateTimeDisplay() {
        // Still update the display when paused, just don't change the remaining time
        if isBreakActive {
            return // Don't update during a break
        }
        
        if isPaused {
            // When paused, just format the stored remaining time
            timeUntilBreakFormatted = formatTime(seconds: Int(remainingTimeUntilBreak))
            return
        }
        
        // Normal case - timer is running
        if let startTime = timerStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            let totalTime = TimeInterval(breakFrequencyMinutes * 60)
            let remaining = max(0, totalTime - elapsed)
            
            remainingTimeUntilBreak = remaining
            timeUntilBreakFormatted = formatTime(seconds: Int(remaining))
        }
    }
    
    // Add methods for pausing and resuming the timer
    func pauseTimer() {
        guard !isPaused && !isBreakActive else { return }
        
        // Store the remaining time
        if let startTime = timerStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            let totalTime = TimeInterval(breakFrequencyMinutes * 60)
            remainingTimeUntilBreak = max(0, totalTime - elapsed)
        }
        
        // Invalidate the current timer
        timer?.invalidate()
        timer = nil
        timerStartTime = nil
        
        // Set paused state
        isPaused = true
        
        print("Timer paused with \(formatTime(seconds: Int(remainingTimeUntilBreak))) remaining")
    }
    
    func resumeTimer() {
        guard isPaused && !isBreakActive else { return }
        
        // Create a new timer with the remaining time
        timer?.invalidate()
        
        // Set the new start time based on the remaining time
        timerStartTime = Date()
        
        // Create a new timer that runs in all modes
        let resumedTimer = Timer(timeInterval: remainingTimeUntilBreak, repeats: false) { [weak self] _ in
            self?.triggerBreak()
        }
        // Add to common run loop mode
        RunLoop.main.add(resumedTimer, forMode: .common)
        self.timer = resumedTimer
        
        // Reset paused state
        isPaused = false
        
        print("Timer resumed with \(formatTime(seconds: Int(remainingTimeUntilBreak))) remaining")
    }
    
    func togglePauseResume() {
        if isPaused {
            resumeTimer()
        } else {
            pauseTimer()
        }
    }
}

// SwiftUI Settings View
struct SettingsView: View {
    @Binding var frequencyMinutes: Int
    @Binding var durationSeconds: Int
    var isPaused: () -> Bool
    var timeUntilBreak: () -> String
    var onSettingsChanged: () -> Void
    var onPauseResumeToggled: () -> Void
    
    // Range of values
    let frequencyRange: ClosedRange<Double> = 1...60
    let durationRange: ClosedRange<Double> = 5...120
    
    // State for sliders
    @State private var frequencyValue: Double
    @State private var durationValue: Double
    
    // State to force UI refreshes
    @State private var activeTrigger = false
    
    // Timer to update the UI frequently
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    // Store the text value to detect changes
    @State private var lastTimeString: String = ""
    
    init(frequencyMinutes: Binding<Int>, 
         durationSeconds: Binding<Int>, 
         isPaused: @escaping () -> Bool,
         timeUntilBreak: @escaping () -> String,
         onSettingsChanged: @escaping () -> Void,
         onPauseResumeToggled: @escaping () -> Void) {
        
        self._frequencyMinutes = frequencyMinutes
        self._durationSeconds = durationSeconds
        self.isPaused = isPaused
        self.timeUntilBreak = timeUntilBreak
        self.onSettingsChanged = onSettingsChanged
        self.onPauseResumeToggled = onPauseResumeToggled
        
        // Initialize slider states
        self._frequencyValue = State(initialValue: Double(frequencyMinutes.wrappedValue))
        self._durationValue = State(initialValue: Double(durationSeconds.wrappedValue))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WalkAway Settings")
                .font(.title3)
                .frame(maxWidth: .infinity, alignment: .center)
            
            Divider()
            
            // Time until next break
            VStack(alignment: .center, spacing: 2) {
                Text("Next Break In:")
                    .font(.headline)
                
                // Using a private variable to help force refreshes
                let currentTime = timeUntilBreak()
                
                Text(currentTime)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(.blue)
                    .frame(height: 30)
                    .id("timer-\(currentTime)-\(activeTrigger)")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            
            // Use timer to update UI
            .onReceive(timer) { _ in
                // Update active trigger to force refresh
                let current = timeUntilBreak()
                if current != lastTimeString {
                    lastTimeString = current
                    activeTrigger.toggle()
                }
            }
            
            // Pause/Resume Button
            Button {
                onPauseResumeToggled()
            } label: {
                Label(isPaused() ? "Resume Timer" : "Pause Timer", 
                      systemImage: isPaused() ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(isPaused() ? .green : .orange)
            .controlSize(.small)
            
            Divider()
            
            // Frequency and Duration settings
            Group {
                // Frequency Setting
                VStack(alignment: .leading, spacing: 2) {
                    Text("Break Frequency: \(Int(frequencyValue)) min")
                        .font(.subheadline)
                    Slider(value: $frequencyValue, in: frequencyRange, step: 1) {
                        // Empty label
                    } minimumValueLabel: {
                        Text("\(Int(frequencyRange.lowerBound))m")
                            .font(.caption)
                    } maximumValueLabel: {
                        Text("\(Int(frequencyRange.upperBound))m")
                            .font(.caption)
                    }
                    .onChange(of: frequencyValue) { newValue in
                        let newIntValue = Int(newValue)
                        if newIntValue != frequencyMinutes {
                            frequencyMinutes = newIntValue
                            onSettingsChanged()
                        }
                    }
                }
                
                // Duration Setting
                VStack(alignment: .leading, spacing: 2) {
                    Text("Break Duration: \(Int(durationValue)) sec")
                        .font(.subheadline)
                    Slider(value: $durationValue, in: durationRange, step: 5) {
                        // Empty label
                    } minimumValueLabel: {
                        Text("\(Int(durationRange.lowerBound))s")
                            .font(.caption)
                    } maximumValueLabel: {
                        Text("\(Int(durationRange.upperBound))s")
                            .font(.caption)
                    }
                    .onChange(of: durationValue) { newValue in
                        let newIntValue = Int(newValue)
                        if newIntValue != durationSeconds {
                            durationSeconds = newIntValue
                            onSettingsChanged()
                        }
                    }
                }
            }
            
            Spacer(minLength: 5)
            
            Divider()
            
            // Quit Button
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit WalkAway", systemImage: "xmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.regular)
            .keyboardShortcut("q", modifiers: [.command])
        }
        .padding(12)
        .frame(width: 300, height: 380)
        .onAppear {
            // Store initial time
            lastTimeString = timeUntilBreak()
        }
    }
}
