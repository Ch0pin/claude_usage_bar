import Foundation

// MARK: - Raw API response
//
// Shape of GET https://api.anthropic.com/api/oauth/usage (the endpoint behind
// Claude Code's `/usage`). Every field is optional so new or missing keys do
// not break decoding.

struct OAuthUsageResponse: Decodable {
    struct Window: Decodable {
        let utilization: Double?
        let resetsAt: String?
    }

    struct Limit: Decodable {
        struct Scope: Decodable {
            struct Model: Decodable {
                let displayName: String?
            }
            let model: Model?
        }

        let kind: String?
        let group: String?
        let percent: Double?
        let resetsAt: String?
        let scope: Scope?
        let isActive: Bool?
    }

    struct ExtraUsage: Decodable {
        let isEnabled: Bool?
        let monthlyLimit: Double?
        let usedCredits: Double?
        let utilization: Double?
        let currency: String?
        let decimalPlaces: Int?
    }

    let fiveHour: Window?
    let sevenDay: Window?
    let sevenDayOpus: Window?
    let sevenDaySonnet: Window?
    let extraUsage: ExtraUsage?
    let limits: [Limit]?

    static func decode(_ data: Data) throws -> OAuthUsageResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(OAuthUsageResponse.self, from: data)
        } catch {
            throw UsageError.invalidResponse
        }
    }

    func snapshot(credentials: ClaudeCredentials?, fetchedAt: Date = Date()) throws -> UsageSnapshot {
        var session = fiveHour.flatMap { window -> LimitReading? in
            guard let used = window.utilization else { return nil }
            return LimitReading(id: "session", title: "Current session", usedPercent: used,
                                resetsAt: Self.parseDate(window.resetsAt), isActive: true)
        }

        // Some responses only carry the session window inside `limits`.
        if session == nil,
           let limit = limits?.first(where: { ($0.group ?? $0.kind ?? "").contains("session") || $0.kind == "five_hour" }),
           let used = limit.percent {
            session = LimitReading(id: "session", title: "Current session", usedPercent: used,
                                   resetsAt: Self.parseDate(limit.resetsAt), isActive: limit.isActive ?? true)
        }

        var weekly = sevenDay.flatMap { window -> LimitReading? in
            guard let used = window.utilization else { return nil }
            return LimitReading(id: "weekly", title: "Weekly · all models", usedPercent: used,
                                resetsAt: Self.parseDate(window.resetsAt), isActive: true)
        }

        if weekly == nil,
           let limit = limits?.first(where: { $0.kind == "weekly_all" }),
           let used = limit.percent {
            weekly = LimitReading(id: "weekly", title: "Weekly · all models", usedPercent: used,
                                  resetsAt: Self.parseDate(limit.resetsAt), isActive: limit.isActive ?? true)
        }

        var scoped: [LimitReading] = []
        if let limits {
            for (index, limit) in limits.enumerated() where limit.kind == "weekly_scoped" {
                guard let used = limit.percent else { continue }
                let name = limit.scope?.model?.displayName ?? "Model"
                scoped.append(LimitReading(id: "scoped-\(index)-\(name)", title: "Weekly · \(name)",
                                           usedPercent: used, resetsAt: Self.parseDate(limit.resetsAt),
                                           isActive: limit.isActive ?? true))
            }
        } else {
            for (id, name, window) in [("opus", "Opus", sevenDayOpus), ("sonnet", "Sonnet", sevenDaySonnet)] {
                guard let window, let used = window.utilization else { continue }
                scoped.append(LimitReading(id: "scoped-\(id)", title: "Weekly · \(name)", usedPercent: used,
                                           resetsAt: Self.parseDate(window.resetsAt), isActive: true))
            }
        }

        guard session != nil || weekly != nil else {
            throw UsageError.noLimitsReturned
        }

        var extra: ExtraUsageReading?
        if let extraUsage, extraUsage.isEnabled == true {
            let divisor = pow(10, Double(extraUsage.decimalPlaces ?? 2))
            extra = ExtraUsageReading(
                used: (extraUsage.usedCredits ?? 0) / divisor,
                limit: extraUsage.monthlyLimit.map { $0 / divisor },
                currency: extraUsage.currency ?? "USD"
            )
        }

        return UsageSnapshot(
            session: session,
            weekly: weekly,
            scoped: scoped,
            extraUsage: extra,
            planName: Self.planName(subscriptionType: credentials?.subscriptionType,
                                    tier: credentials?.rateLimitTier),
            fetchedAt: fetchedAt
        )
    }

    /// Parses ISO 8601 timestamps such as `2026-11-13T06:59:59.870563+00:00`.
    /// Fractional seconds are dropped because the system formatter rejects
    /// more than three fractional digits on some macOS releases.
    static func parseDate(_ value: String?) -> Date? {
        guard var text = value, !text.isEmpty else { return nil }
        if let dot = text.firstIndex(of: ".") {
            let fractionEnd = text[text.index(after: dot)...].firstIndex(where: { !$0.isNumber }) ?? text.endIndex
            text.removeSubrange(dot..<fractionEnd)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    static func planName(subscriptionType: String?, tier: String?) -> String? {
        guard let type = subscriptionType?.lowercased(), !type.isEmpty else { return nil }
        let tier = tier?.lowercased() ?? ""
        switch type {
        case "pro": return "Claude Pro"
        case "max":
            if tier.contains("20x") { return "Claude Max 20x" }
            if tier.contains("5x") { return "Claude Max 5x" }
            return "Claude Max"
        case "team": return "Claude Team"
        case "enterprise": return "Claude Enterprise"
        case "free": return "Claude Free"
        default: return "Claude " + type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

// MARK: - Display model

struct LimitReading: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let usedPercent: Double
    let resetsAt: Date?
    let isActive: Bool

    var remainingPercent: Double {
        min(100, max(0, 100 - usedPercent))
    }
}

struct ExtraUsageReading: Codable, Equatable {
    let used: Double
    let limit: Double?
    let currency: String
}

struct UsageSnapshot: Codable, Equatable {
    let session: LimitReading?
    let weekly: LimitReading?
    let scoped: [LimitReading]
    let extraUsage: ExtraUsageReading?
    let planName: String?
    let fetchedAt: Date

    /// Remaining percent of whichever reported limit is closest to running out.
    /// Limits the plan does not have (for example no 5-hour window) are ignored.
    var tightestRemainingPercent: Double {
        [session, weekly].compactMap { $0?.remainingPercent }.min() ?? 100
    }

    /// The menu-bar sources that make sense for this account. Without a
    /// session window, only the weekly limit applies.
    var availableSources: [GaugeSource] {
        switch (session != nil, weekly != nil) {
        case (true, true): return GaugeSource.allCases
        case (true, false): return [.session]
        default: return [.weekly]
        }
    }

    func effectiveSource(_ preferred: GaugeSource) -> GaugeSource {
        let available = availableSources
        return available.contains(preferred) ? preferred : available[0]
    }
}

/// Which limit the menu-bar gauge represents.
enum GaugeSource: String, CaseIterable, Identifiable {
    case tightest
    case session
    case weekly
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tightest: return "Tightest limit"
        case .session: return "Current session (5h)"
        case .weekly: return "Weekly limit"
        case .both: return "Session + weekly (split)"
        }
    }
}

/// The shape drawn in the menu bar.
enum GaugeStyle: String, CaseIterable, Identifiable {
    case bar
    case segments
    case ring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bar: return "Bar"
        case .segments: return "Segments"
        case .ring: return "Ring"
        }
    }
}

enum UsageLevel: Equatable {
    case normal
    case warning
    case critical
    case unknown

    init(remainingPercent: Double) {
        switch remainingPercent {
        case ...10: self = .critical
        case ...25: self = .warning
        default: self = .normal
        }
    }
}

// MARK: - Errors

enum UsageError: LocalizedError {
    case notSignedIn
    case signInExpired
    case unauthorized
    case rateLimited
    case http(Int)
    case network(String)
    case invalidResponse
    case noLimitsReturned
    case timedOut
    case iconRender(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "No Claude Code sign-in found. Install Claude Code and run `claude` to sign in with your Claude account."
        case .signInExpired, .unauthorized:
            return "Your Claude Code sign-in has expired. Run `claude` once in a terminal to refresh it."
        case .rateLimited:
            return "Claude is rate-limiting usage requests. The bar will retry at the next refresh."
        case .http(let status):
            return "Claude's usage service returned HTTP \(status)."
        case .network(let detail):
            return "Could not reach Claude: \(detail)"
        case .invalidResponse:
            return "Claude returned an unreadable usage response."
        case .noLimitsReturned:
            return "Claude did not return any plan limits for this account. Usage limits are only available for Claude subscription plans."
        case .timedOut:
            return "The usage refresh timed out after 15 seconds."
        case .iconRender(let detail):
            return "Icon rendering failed: \(detail)"
        }
    }
}
