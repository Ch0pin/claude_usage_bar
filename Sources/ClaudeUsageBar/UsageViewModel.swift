import AppKit
import Foundation
import ServiceManagement

@MainActor
final class UsageViewModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?

    @Published var gaugeSource: GaugeSource {
        didSet { UserDefaults.standard.set(gaugeSource.rawValue, forKey: Keys.gaugeSource) }
    }

    @Published var gaugeStyle: GaugeStyle {
        didSet { UserDefaults.standard.set(gaugeStyle.rawValue, forKey: Keys.gaugeStyle) }
    }

    @Published var showPercentage: Bool {
        didSet { UserDefaults.standard.set(showPercentage, forKey: Keys.showPercentage) }
    }

    @Published private(set) var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    private enum Keys {
        static let snapshot = "lastUsageSnapshot"
        static let gaugeSource = "gaugeSource"
        static let gaugeStyle = "gaugeStyle"
        static let showPercentage = "showPercentage"
    }

    private let client = ClaudeUsageClient()
    private let refreshInterval: TimeInterval = 300
    private var refreshTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    init() {
        let defaults = UserDefaults.standard
        gaugeSource = defaults.string(forKey: Keys.gaugeSource)
            .flatMap(GaugeSource.init(rawValue:)) ?? .tightest
        gaugeStyle = defaults.string(forKey: Keys.gaugeStyle)
            .flatMap(GaugeStyle.init(rawValue:)) ?? .bar
        showPercentage = defaults.object(forKey: Keys.showPercentage) as? Bool ?? true

        loadCache()
        refresh()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        // Refresh shortly after wake, once the network is back.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    // MARK: - Menu-bar presentation

    /// Sources offered in the settings: only the limits this account has.
    var availableSources: [GaugeSource] {
        snapshot?.availableSources ?? GaugeSource.allCases
    }

    var gauge: Gauge {
        guard let snapshot else { return Gauge(style: gaugeStyle, fills: [], level: .unknown) }
        let level = UsageLevel(remainingPercent: displayedRemainingPercent(snapshot))

        if snapshot.effectiveSource(gaugeSource) == .both,
           let session = snapshot.session, let weekly = snapshot.weekly {
            return Gauge(style: gaugeStyle,
                         fills: [session.remainingPercent / 100, weekly.remainingPercent / 100],
                         level: level)
        }
        return Gauge(style: gaugeStyle, fills: [displayedRemainingPercent(snapshot) / 100], level: level)
    }

    /// The percentage shown next to the gauge: what is left.
    var menuBarText: String {
        guard let snapshot else { return isRefreshing ? "…" : "--" }
        return "\(Int(displayedRemainingPercent(snapshot).rounded()))%"
    }

    var tooltip: String {
        guard let snapshot else { return errorMessage ?? "Claude usage: loading…" }
        var lines: [String] = []
        if let session = snapshot.session {
            lines.append("Session: \(Int(session.remainingPercent.rounded()))% left")
        }
        if let weekly = snapshot.weekly {
            lines.append("Weekly: \(Int(weekly.remainingPercent.rounded()))% left")
        }
        if errorMessage != nil { lines.append("Last refresh failed. Showing cached values.") }
        return lines.joined(separator: "\n")
    }

    private func displayedRemainingPercent(_ snapshot: UsageSnapshot) -> Double {
        switch snapshot.effectiveSource(gaugeSource) {
        case .tightest, .both: return snapshot.tightestRemainingPercent
        case .session: return snapshot.session?.remainingPercent ?? snapshot.tightestRemainingPercent
        case .weekly: return snapshot.weekly?.remainingPercent ?? snapshot.tightestRemainingPercent
        }
    }

    // MARK: - Actions

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil

        Task {
            do {
                let newSnapshot = try await client.fetchUsage()
                snapshot = newSnapshot
                saveCache(newSnapshot)
            } catch {
                errorMessage = error.localizedDescription
            }
            isRefreshing = false
        }
    }

    /// Called when the popover opens, so a quick glance gets fresh numbers
    /// without hitting the endpoint on every click.
    func refreshIfStale(maxAge: TimeInterval = 60) {
        guard let snapshot else { refresh(); return }
        if Date().timeIntervalSince(snapshot.fetchedAt) > maxAge {
            refresh()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = "Could not change the login item: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Cache

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: Keys.snapshot),
              let value = try? JSONDecoder().decode(UsageSnapshot.self, from: data)
        else { return }
        snapshot = value
    }

    private func saveCache(_ value: UsageSnapshot) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: Keys.snapshot)
    }
}
