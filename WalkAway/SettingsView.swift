//
//  SettingsView.swift
//  WalkAway
//

import SwiftUI

/// A snapshot of the work timer for the popover.
struct TimerStatus {
    enum State {
        case running, paused, inMeeting, away
    }

    var state: State
    var remaining: TimeInterval
    var total: TimeInterval
    var nextBreakIsLong: Bool
    var nextBreakSeconds: Int

    static let placeholder = TimerStatus(state: .running, remaining: 0, total: 1, nextBreakIsLong: false, nextBreakSeconds: 30)
}

/// The menu bar popover: timer status at the top, settings below.
struct SettingsView: View {
    @Binding var frequencyMinutes: Int
    @Binding var shortBreakDurationSeconds: Int
    @Binding var longBreakDurationSeconds: Int
    @Binding var launchAtLoginEnabled: Bool
    @Binding var pauseForMeetingAppsEnabled: Bool
    @Binding var inactivityThresholdMinutes: Int

    var status: () -> TimerStatus
    var onSettingsChanged: () -> Void
    var onPauseResumeToggled: () -> Void
    var onLaunchSettingChanged: () -> Void

    // Bumped after Pause/Resume so the header updates without waiting for the next tick
    @State private var refreshToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let _ = refreshToken
                StatusHeader(status: status()) {
                    onPauseResumeToggled()
                    refreshToken += 1
                }
            }

            SettingsSection("Schedule", footer: "Every third break is a long one and can't be skipped.") {
                PickerRow("Break every", selection: $frequencyMinutes, values: Array(stride(from: 30, through: 120, by: 10))) { "\($0) min" }
                Divider()
                PickerRow("Short break", selection: $shortBreakDurationSeconds, values: Array(stride(from: 30, through: 180, by: 30))) { "\($0) sec" }
                Divider()
                PickerRow("Long break", selection: $longBreakDurationSeconds, values: Array(stride(from: 300, through: 1800, by: 300))) { "\($0 / 60) min" }
            }

            SettingsSection("Smart pausing") {
                ToggleRow("Pause during meetings", isOn: $pauseForMeetingAppsEnabled)
                Divider()
                PickerRow("Reset when away for", selection: $inactivityThresholdMinutes, values: Array(stride(from: 5, through: 60, by: 5))) { "\($0) min" }
            }

            SettingsSection("General") {
                ToggleRow("Launch at login", isOn: $launchAtLoginEnabled)
            }

            HStack {
                Text("WalkAway")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onChange(of: frequencyMinutes) { onSettingsChanged() }
        .onChange(of: shortBreakDurationSeconds) { onSettingsChanged() }
        .onChange(of: longBreakDurationSeconds) { onSettingsChanged() }
        .onChange(of: launchAtLoginEnabled) { onLaunchSettingChanged() }
    }
}

// MARK: - Status Header

private struct StatusHeader: View {
    let status: TimerStatus
    let onPauseResume: () -> Void

    private var isPaused: Bool { status.state == .paused || status.state == .inMeeting }

    var body: some View {
        HStack(spacing: 14) {
            ProgressRing(progress: progress, tint: tint) {
                Text(timeText)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            pauseButton
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var pauseButton: some View {
        let button = Button(action: onPauseResume) {
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .frame(width: 20, height: 20)
        }
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .disabled(status.state == .inMeeting)
        .help(isPaused ? "Resume timer" : "Pause timer")
        .accessibilityLabel(isPaused ? "Resume timer" : "Pause timer")

        if #available(macOS 26, *) {
            button.buttonStyle(.glass)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var progress: Double {
        guard status.state != .away, status.total > 0 else { return 1 }
        return min(max(status.remaining / status.total, 0), 1)
    }

    private var tint: Color {
        switch status.state {
        case .running: .accentColor
        case .paused, .inMeeting: .orange
        case .away: .secondary
        }
    }

    private var timeText: String {
        let seconds = Int((status.state == .away ? status.total : status.remaining).rounded(.up))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var title: String {
        switch status.state {
        case .running: "Next break"
        case .paused: "Paused"
        case .inMeeting: "In a meeting"
        case .away: "Away"
        }
    }

    private var subtitle: String {
        switch status.state {
        case .running:
            let length = status.nextBreakSeconds < 60 ? "\(status.nextBreakSeconds) sec" : "\(status.nextBreakSeconds / 60) min"
            return "\(status.nextBreakIsLong ? "Long" : "Short") break, \(length)"
        case .paused: return "Resume when you're ready"
        case .inMeeting: return "Resumes when the call ends"
        case .away: return "Starts when you're back"
        }
    }
}

private struct ProgressRing<Label: View>: View {
    var progress: Double
    var tint: Color
    @ViewBuilder var label: Label

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: progress)
            label
        }
    }
}

// MARK: - Settings Rows

private struct SettingsSection<Content: View>: View {
    let title: String
    let footer: String?
    let content: Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 12)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }
}

private struct PickerRow: View {
    let title: String
    @Binding var selection: Int
    let values: [Int]
    let label: (Int) -> String

    init(_ title: String, selection: Binding<Int>, values: [Int], label: @escaping (Int) -> String) {
        self.title = title
        self._selection = selection
        self.values = values
        self.label = label
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Picker(title, selection: $selection) {
                ForEach(values, id: \.self) { value in
                    Text(label(value)).tag(value)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
        .frame(minHeight: 36)
    }
}

private struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .frame(minHeight: 36)
    }
}

// MARK: - Previews

#Preview("Running") {
    SettingsView(
        frequencyMinutes: .constant(30),
        shortBreakDurationSeconds: .constant(30),
        longBreakDurationSeconds: .constant(300),
        launchAtLoginEnabled: .constant(false),
        pauseForMeetingAppsEnabled: .constant(true),
        inactivityThresholdMinutes: .constant(10),
        status: { TimerStatus(state: .running, remaining: 1012, total: 1800, nextBreakIsLong: false, nextBreakSeconds: 30) },
        onSettingsChanged: {},
        onPauseResumeToggled: {},
        onLaunchSettingChanged: {}
    )
}

#Preview("In a meeting") {
    SettingsView(
        frequencyMinutes: .constant(30),
        shortBreakDurationSeconds: .constant(30),
        longBreakDurationSeconds: .constant(300),
        launchAtLoginEnabled: .constant(true),
        pauseForMeetingAppsEnabled: .constant(true),
        inactivityThresholdMinutes: .constant(10),
        status: { TimerStatus(state: .inMeeting, remaining: 540, total: 1800, nextBreakIsLong: true, nextBreakSeconds: 300) },
        onSettingsChanged: {},
        onPauseResumeToggled: {},
        onLaunchSettingChanged: {}
    )
}
