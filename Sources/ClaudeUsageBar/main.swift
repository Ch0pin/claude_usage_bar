import AppKit
import Darwin

// Command-line helpers used by the build script and for diagnostics.
let arguments = CommandLine.arguments

if let index = arguments.firstIndex(of: "--create-icns"), arguments.indices.contains(index + 2) {
    do {
        try ICNSBuilder.create(from: URL(fileURLWithPath: arguments[index + 1]),
                               outputURL: URL(fileURLWithPath: arguments[index + 2]))
        print(arguments[index + 2])
        exit(EXIT_SUCCESS)
    } catch {
        fputs("ICNS creation failed: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

if let index = arguments.firstIndex(of: "--render-app-icon"), arguments.indices.contains(index + 1) {
    do {
        try AppIconRenderer.writePNG(to: URL(fileURLWithPath: arguments[index + 1]))
        print(arguments[index + 1])
        exit(EXIT_SUCCESS)
    } catch {
        fputs("App icon rendering failed: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

if let index = arguments.firstIndex(of: "--render-gauge-preview"), arguments.indices.contains(index + 1) {
    do {
        try GaugePreview.writePNG(to: URL(fileURLWithPath: arguments[index + 1]))
        print(arguments[index + 1])
        exit(EXIT_SUCCESS)
    } catch {
        fputs("Preview rendering failed: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

if arguments.contains("--check") {
    // Prints only percentages and reset times, never credentials.
    do {
        let snapshot = try ClaudeUsageClient().fetchUsageSynchronously()
        let iso = ISO8601DateFormatter()
        print("plan=\(snapshot.planName ?? "unknown")")
        if let session = snapshot.session {
            print("session_used_percent=\(Int(session.usedPercent.rounded()))")
            if let reset = session.resetsAt { print("session_resets_at=\(iso.string(from: reset))") }
        } else {
            print("session_window=none")
        }
        if let weekly = snapshot.weekly {
            print("weekly_used_percent=\(Int(weekly.usedPercent.rounded()))")
            if let reset = weekly.resetsAt { print("weekly_resets_at=\(iso.string(from: reset))") }
        }
        for scoped in snapshot.scoped {
            print("scoped \"\(scoped.title)\" used_percent=\(Int(scoped.usedPercent.rounded()))")
        }
        print("gauge_remaining_percent=\(Int(snapshot.tightestRemainingPercent.rounded()))")
        exit(EXIT_SUCCESS)
    } catch {
        fputs("Claude Usage Bar check failed: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

// Menu-bar app: no Dock icon, no main window.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
