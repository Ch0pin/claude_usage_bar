import Foundation

// MARK: - Credentials

/// The Claude Code OAuth sign-in. The access token is used only for the
/// request header. It is never logged, cached, or written anywhere.
struct ClaudeCredentials {
    let accessToken: String
    let expiresAt: Date?
    let subscriptionType: String?
    let rateLimitTier: String?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow < 60
    }
}

enum CredentialStore {
    static let keychainService = "Claude Code-credentials"

    /// Loads Claude Code's sign-in from the macOS Keychain, falling back to
    /// `~/.claude/.credentials.json`. If both exist, the later-expiring one wins.
    static func load() throws -> ClaudeCredentials {
        var candidates: [ClaudeCredentials] = []
        if let data = keychainData(), let credentials = parse(data) {
            candidates.append(credentials)
        }
        if let data = try? Data(contentsOf: credentialsFileURL()), let credentials = parse(data) {
            candidates.append(credentials)
        }
        guard let best = candidates.max(by: {
            ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture)
        }) else {
            throw UsageError.notSignedIn
        }
        return best
    }

    /// Reads the item through `/usr/bin/security`, the same tool Claude Code
    /// uses, so the item's existing access list applies. Calling the Keychain
    /// API directly would ask for access again after every ad-hoc rebuild.
    private static func keychainData() -> Data? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else { return nil }
        return data
    }

    private static func credentialsFileURL() -> URL {
        if let configDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !configDir.isEmpty {
            return URL(fileURLWithPath: configDir).appendingPathComponent(".credentials.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
    }

    private static func parse(_ data: Data) -> ClaudeCredentials? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else { return nil }

        let expiresAt = (oauth["expiresAt"] as? NSNumber)
            .map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }

        return ClaudeCredentials(
            accessToken: token,
            expiresAt: expiresAt,
            subscriptionType: oauth["subscriptionType"] as? String,
            rateLimitTier: oauth["rateLimitTier"] as? String
        )
    }
}

// MARK: - Usage client

struct ClaudeUsageClient {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let timeout: TimeInterval = 15

    func fetchUsage() async throws -> UsageSnapshot {
        try await Task.detached(priority: .utility) {
            try fetchUsageSynchronously()
        }.value
    }

    func fetchUsageSynchronously() throws -> UsageSnapshot {
        var credentials = try CredentialStore.load()

        if credentials.isExpired {
            credentials = try refreshThroughClaudeCode()
        }

        do {
            return try requestUsage(with: credentials)
        } catch UsageError.unauthorized {
            let refreshed = try refreshThroughClaudeCode()
            do {
                return try requestUsage(with: refreshed)
            } catch UsageError.unauthorized {
                throw UsageError.signInExpired
            }
        }
    }

    private func requestUsage(with credentials: ClaudeCredentials) throws -> UsageSnapshot {
        var request = URLRequest(url: Self.endpoint,
                                 cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: timeout)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("claude-usage-bar/0.1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try perform(request)
        switch response.statusCode {
        case 200:
            return try OAuthUsageResponse.decode(data).snapshot(credentials: credentials)
        case 401, 403:
            throw UsageError.unauthorized
        case 429:
            throw UsageError.rateLimited
        default:
            throw UsageError.http(response.statusCode)
        }
    }

    private func perform(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        final class ResultBox: @unchecked Sendable {
            var result: Result<(Data, HTTPURLResponse), Error> = .failure(UsageError.timedOut)
        }
        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                let nsError = error as NSError
                box.result = .failure(nsError.code == NSURLErrorTimedOut
                    ? UsageError.timedOut
                    : UsageError.network(nsError.localizedDescription))
            } else if let http = response as? HTTPURLResponse {
                box.result = .success((data ?? Data(), http))
            } else {
                box.result = .failure(UsageError.invalidResponse)
            }
            semaphore.signal()
        }
        task.resume()

        if semaphore.wait(timeout: .now() + timeout + 2) == .timedOut {
            task.cancel()
            throw UsageError.timedOut
        }
        return try box.result.get()
    }

    /// The app never refreshes or rewrites Claude Code's tokens itself, so it
    /// cannot conflict with Claude Code. Instead it runs the lightweight
    /// `claude auth status` command, which uses no model quota, so Claude Code
    /// can refresh its own sign-in, and then reads the credentials again.
    private func refreshThroughClaudeCode() throws -> ClaudeCredentials {
        if let claude = claudeExecutableURL() {
            let process = Process()
            process.executableURL = claude
            process.arguments = ["auth", "status"]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.environment = childEnvironment(for: claude)
            if (try? process.run()) != nil {
                let deadline = Date().addingTimeInterval(20)
                while process.isRunning, Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.1)
                }
                if process.isRunning { process.terminate() }
            }
        }

        let credentials = try CredentialStore.load()
        if credentials.isExpired {
            throw UsageError.signInExpired
        }
        return credentials
    }

    private func claudeExecutableURL() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates: [String] = []

        if let override = environment["CLAUDE_USAGE_BAR_CLAUDE_PATH"], !override.isEmpty {
            candidates.append(override)
        }
        candidates.append(contentsOf: [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude"
        ])
        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/claude" })
        }

        return candidates
            .first(where: FileManager.default.isExecutableFile(atPath:))
            .map(URL.init(fileURLWithPath:))
    }

    /// Finder-launched apps get a minimal PATH. This adds the common install
    /// locations so npm-based Claude Code installs can find `node`.
    private func childEnvironment(for executable: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let existing = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        let required = [
            executable.deletingLastPathComponent().path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        environment["PATH"] = (required + existing)
            .reduce(into: [String]()) { paths, path in
                if !paths.contains(path) { paths.append(path) }
            }
            .joined(separator: ":")
        return environment
    }
}
