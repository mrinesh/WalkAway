# WalkAway - Break Reminder App

WalkAway is a simple macOS menu bar application that helps you remember to take breaks at regular intervals. When it's time for a break, the app displays a full-screen overlay with a motivational message, encouraging you to stand up, look away from your screen, and take a short break.

## Features

- Lives in your menu bar with a simple icon
- Customizable break frequency (1-60 minutes)
- Customizable break duration (5-120 seconds)
- Full-screen overlay with a navy blue theme
- Motivational messages during breaks
- Countdown timer showing remaining break time
- Option to skip a break if needed

## How to Use

1. Run the application. An eye icon will appear in your menu bar.
2. Click the icon to access settings:
   - **Break Frequency**: How often should breaks occur (in minutes)
   - **Break Duration**: How long each break should last (in seconds)
3. When it's time for a break, a full-screen overlay will appear.
4. Wait for the break timer to complete, or click "Skip Break" to end it early.
5. To quit the app, click the menu bar icon and then click "Quit WalkAway" or use Cmd+Q.

## Why Regular Breaks Matter

Taking regular breaks from screen work can help reduce eye strain, prevent repetitive strain injuries, improve focus, and boost productivity. The 20-20-20 rule (every 20 minutes, look at something 20 feet away for 20 seconds) is a good practice that this app can help you follow.

## Technical Notes

- Built with Swift, AppKit, and SwiftUI
- Runs on macOS 11.0 (Big Sur) or later
- Implemented as a menu bar application (LSUIElement) 