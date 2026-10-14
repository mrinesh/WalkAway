//
//  MediaController.swift
//  WalkAway
//

import Foundation

/// Pauses system-wide "Now Playing" media (Safari/Chrome video, Music, Spotify, etc.).
///
/// Since macOS 15.4, mediaremoted only answers Apple-entitled processes, so this app can't
/// read playback state itself. Apple's /usr/bin/perl is entitled, so the work is done there
/// via PerlObjCBridge. If that fails, an explicit (idempotent) pause is sent directly.
final class MediaController {
    static let shared = MediaController()

    private static let perlPath = "/usr/bin/perl"
    private static let mediaRemotePath = "/System/Library/PrivateFrameworks/MediaRemote.framework"
    private static let kMRPause = 1

    private static let pauseScript = """
    use Foundation;
    NSBundle->bundleWithPath_("\(mediaRemotePath)")->load or exit 2;
    @MRNowPlayingRequest::ISA = qw(PerlObjCBridge);
    @MRNowPlayingController::ISA = qw(PerlObjCBridge);
    if (MRNowPlayingRequest->localIsPlaying) {
        MRNowPlayingController->localRouteController->sendCommand_options_completion_(\(kMRPause), undef, undef);
        NSRunLoop->currentRunLoop->runUntilDate_(NSDate->dateWithTimeIntervalSinceNow_(0.3));
        print "paused";
    } else {
        print "not-playing";
    }
    """

    private typealias MRMediaRemoteSendCommandFunction = @convention(c) (Int, AnyObject?) -> Bool
    private let sendCommand: MRMediaRemoteSendCommandFunction?

    private init() {
        if let bundle = CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: Self.mediaRemotePath)),
           let pointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) {
            sendCommand = unsafeBitCast(pointer, to: MRMediaRemoteSendCommandFunction.self)
        } else {
            sendCommand = nil
        }
    }

    /// Pauses whatever is currently playing (if anything). Never resumes paused media.
    func pauseIfPlaying() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.perlPath)
        process.arguments = ["-e", Self.pauseScript]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        process.terminationHandler = { [weak self] proc in
            let result = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                if proc.terminationStatus == 0 {
                    print("[MediaController] \(result == "paused" ? "Media was playing; paused it" : "No media currently playing")")
                } else {
                    print("[MediaController] Perl helper failed (status \(proc.terminationStatus)); sending direct pause")
                    self?.sendDirectPause()
                }
            }
        }

        do {
            try process.run()
        } catch {
            print("[MediaController] Couldn't launch perl (\(error.localizedDescription)); sending direct pause")
            sendDirectPause()
        }
    }

    private func sendDirectPause() {
        guard let sendCommand else {
            print("[MediaController] MediaRemote unavailable; can't pause media")
            return
        }
        _ = sendCommand(Self.kMRPause, nil)
    }
}
