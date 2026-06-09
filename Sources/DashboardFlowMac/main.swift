import SwiftUI
import WebKit

enum DashboardRoute: String, CaseIterable, Identifiable {
    case flowMap
    case dashboard
    case workflow
    case servers
    case docker
    case cloudflare
    case costs
    case alerts
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flowMap: "Flow Map"
        case .dashboard: "Dashboard"
        case .workflow: "Workflow"
        case .servers: "Server"
        case .docker: "Docker"
        case .cloudflare: "Cloudflare"
        case .costs: "Kosten"
        case .alerts: "Alerts"
        case .profile: "Profil"
        }
    }

    var symbol: String {
        switch self {
        case .flowMap: "point.3.connected.trianglepath.dotted"
        case .dashboard: "chart.bar.xaxis"
        case .workflow: "square.stack.3d.forward.dottedline"
        case .servers: "server.rack"
        case .docker: "shippingbox"
        case .cloudflare: "cloud"
        case .costs: "eurosign.circle"
        case .alerts: "bell.badge"
        case .profile: "person.crop.circle"
        }
    }

    var path: String {
        switch self {
        case .flowMap: "/dashboard"
        case .dashboard: "/dashboard"
        case .workflow: "/workflow"
        case .servers: "/servers"
        case .docker: "/docker"
        case .cloudflare: "/cloudflare"
        case .costs: "/costs"
        case .alerts: "/alerts"
        case .profile: "/profile"
        }
    }
}

struct FlowStep: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
}

let flowSteps = [
    FlowStep(title: "Dashboard", subtitle: "Live-Übersicht für Server, Container, Alerts und DNS.", symbol: "chart.bar.xaxis", tint: .green),
    FlowStep(title: "Server", subtitle: "SSH-Monitoring für Status, CPU, RAM, Disk und Uptime.", symbol: "server.rack", tint: .blue),
    FlowStep(title: "Docker", subtitle: "Container-Status, Ressourcen und Restart-Erkennung.", symbol: "shippingbox", tint: .cyan),
    FlowStep(title: "Services", subtitle: "Health-Checks und Erreichbarkeit deiner Dienste.", symbol: "waveform.path.ecg", tint: .mint),
    FlowStep(title: "Cloudflare", subtitle: "Zones, DNS Records und Sync mit deinem Cloudflare-Account.", symbol: "cloud", tint: .orange),
    FlowStep(title: "Deployments", subtitle: "SSH-basierte Deployments mit Status und Retry.", symbol: "arrow.up.doc", tint: .indigo),
    FlowStep(title: "Kosten", subtitle: "Workspace-Kosten im Blick behalten.", symbol: "eurosign.circle", tint: .yellow),
    FlowStep(title: "Alerts", subtitle: "Warnungen lesen, lösen und Benachrichtigungen auslösen.", symbol: "bell.badge", tint: .red),
    FlowStep(title: "Workflow", subtitle: "Projekt-Bausteine visuell verbinden und dokumentieren.", symbol: "square.stack.3d.forward.dottedline", tint: .purple),
]

struct TokenResponse: Decodable {
    let token: String
}

struct ServerListResponse: Decodable {
    let data: [ServerLoad]
}

struct ServerLoad: Decodable, Identifiable {
    let id: Int
    let name: String
    let hostname: String?
    let status: String
    let latestMetric: ServerMetric?
    let lastPolledAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case hostname
        case status
        case latestMetric = "latest_metric"
        case lastPolledAt = "last_polled_at"
    }

    var cpu: Double? {
        latestMetric?.cpuUsage
    }

    var memoryPercent: Double? {
        guard let metric = latestMetric, metric.memoryTotal > 0 else { return nil }
        return (metric.memoryUsage / metric.memoryTotal) * 100
    }

    var diskPercent: Double? {
        guard let metric = latestMetric, metric.diskTotal > 0 else { return nil }
        return nilIfNaN((metric.diskUsage / metric.diskTotal) * 100)
    }

    private func nilIfNaN(_ value: Double) -> Double? {
        value.isFinite ? value : nil
    }
}

struct ServerMetric: Decodable {
    let cpuUsage: Double
    let memoryUsage: Double
    let memoryTotal: Double
    let diskUsage: Double
    let diskTotal: Double
    let loadAverage: Double?
    let recordedAt: String?

    enum CodingKeys: String, CodingKey {
        case cpuUsage = "cpu_usage"
        case memoryUsage = "memory_usage"
        case memoryTotal = "memory_total"
        case diskUsage = "disk_usage"
        case diskTotal = "disk_total"
        case loadAverage = "load_average"
        case recordedAt = "recorded_at"
    }
}

enum MenuSection: String, CaseIterable, Identifiable {
    case servers = "Server"
    case limits = "Limits"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .servers: "Server-Auslastung"
        case .limits: "KI-Limits"
        }
    }

    var symbol: String {
        switch self {
        case .servers: "server.rack"
        case .limits: "gauge.with.dots.needle.67percent"
        }
    }
}

enum LimitPage: String, CaseIterable, Identifiable {
    case claude = "Claude"
    case codex = "Codex"
    case openAIAPI = "OpenAI API"

    var id: String { rawValue }

    var url: URL {
        switch self {
        case .claude:
            URL(string: "https://claude.ai/settings/usage")!
        case .codex:
            URL(string: "https://chatgpt.com/codex/usage")!
        case .openAIAPI:
            URL(string: "https://platform.openai.com/usage")!
        }
    }
}

struct AIUsageSnapshot: Identifiable, Equatable {
    let id: String
    var name: String
    var detail: String
    var secondary: String
    var status: String
    var symbol: String
    var tint: Color
    var hourTokens: Int
    var hourlyBudget: Int?
    var remainingPercent: Double?
    var limitText: String
}

@MainActor
final class AIUsageMonitor: ObservableObject {
    @Published var snapshots: [AIUsageSnapshot] = []
    @Published var isLoading = false
    @Published var lastUpdated: Date?

    private var refreshTask: Task<Void, Never>?

    func start() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refresh()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        isLoading = true
        let claude = await Task.detached { Self.readClaudeUsage() }.value
        let codex = await Task.detached { Self.readCodexUsage() }.value
        snapshots = [claude, codex]
        lastUpdated = Date()
        isLoading = false
    }

    nonisolated private static func readClaudeUsage() -> AIUsageSnapshot {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let projectsURL = home.appendingPathComponent(".claude/projects")
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? todayStart
        let decoder = JSONDecoder()
        let hourlyBudget = UserDefaults.standard.integer(forKey: "claudeHourlyTokenBudget")

        var messageCount = 0
        var totalTokens = 0
        var hourTokens = 0
        var lastSeen: Date?

        guard let enumerator = FileManager.default.enumerator(
            at: projectsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return AIUsageSnapshot(
                id: "claude",
                name: "Claude",
                detail: "Keine lokalen Daten",
                secondary: "~/.claude/projects nicht gefunden",
                status: "Nicht verbunden",
                symbol: "sparkles",
                tint: .secondary,
                hourTokens: 0,
                hourlyBudget: nil,
                remainingPercent: nil,
                limitText: "Keine lokalen Daten"
            )
        }

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            guard let handle = try? FileHandle(forReadingFrom: fileURL) else { continue }
            defer { try? handle.close() }

            let data = handle.readDataToEndOfFile()
            guard let content = String(data: data, encoding: .utf8) else { continue }

            for line in content.split(separator: "\n") {
                guard let lineData = String(line).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let timestampValue = object["timestamp"] as? String,
                      let timestamp = decoder.date(fromISO8601: timestampValue),
                      timestamp >= todayStart,
                      let message = object["message"] as? [String: Any],
                      let role = message["role"] as? String,
                      role == "assistant",
                      let usage = message["usage"] as? [String: Any]
                else {
                    continue
                }

                messageCount += 1
                totalTokens += usage.intValue("input_tokens")
                totalTokens += usage.intValue("output_tokens")
                totalTokens += usage.intValue("cache_creation_input_tokens")
                totalTokens += usage.intValue("cache_read_input_tokens")

                if timestamp >= hourStart {
                    hourTokens += usage.intValue("input_tokens")
                    hourTokens += usage.intValue("output_tokens")
                    hourTokens += usage.intValue("cache_creation_input_tokens")
                    hourTokens += usage.intValue("cache_read_input_tokens")
                }

                lastSeen = maxDate(lastSeen, timestamp)
            }
        }

        return AIUsageSnapshot(
            id: "claude",
            name: "Claude",
            detail: hourTokens > 0 ? "\(format(hourTokens)) diese Stunde" : "Diese Stunde ruhig",
            secondary: messageCount > 0 ? "\(format(totalTokens)) heute · \(messageCount) Antworten · \(lastSeenText(lastSeen))" : "Quelle: ~/.claude/projects",
            status: "Live lokal",
            symbol: "sparkles",
            tint: .purple,
            hourTokens: hourTokens,
            hourlyBudget: hourlyBudget > 0 ? hourlyBudget : nil,
            remainingPercent: remainingPercent(used: hourTokens, budget: hourlyBudget),
            limitText: hourlyBudget > 0 ? "Budget: \(format(hourlyBudget)) Tokens/Stunde" : "Restlimit nicht lokal verfügbar"
        )
    }

    nonisolated private static func readCodexUsage() -> AIUsageSnapshot {
        let dbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/state_5.sqlite")
            .path

        guard FileManager.default.fileExists(atPath: dbPath) else {
            return AIUsageSnapshot(
                id: "codex",
                name: "Codex",
                detail: "Keine lokalen Daten",
                secondary: "~/.codex/state_5.sqlite nicht gefunden",
                status: "Nicht verbunden",
                symbol: "terminal",
                tint: .secondary,
                hourTokens: 0,
                hourlyBudget: nil,
                remainingPercent: nil,
                limitText: "Keine lokalen Daten"
            )
        }

        let calendar = Calendar.current
        let now = Date()
        let dayStart = Int(calendar.startOfDay(for: now).timeIntervalSince1970)
        let hourStartDate = calendar.dateInterval(of: .hour, for: now)?.start ?? calendar.startOfDay(for: now)
        let hourStart = Int(hourStartDate.timeIntervalSince1970)
        let hourlyBudget = UserDefaults.standard.integer(forKey: "codexHourlyTokenBudget")
        let query = """
        SELECT COALESCE(SUM(tokens_used), 0), COUNT(*), COALESCE(MAX(updated_at), 0),
               COALESCE(SUM(CASE WHEN updated_at >= \(hourStart) THEN tokens_used ELSE 0 END), 0)
        FROM threads
        WHERE updated_at >= \(dayStart);
        """

        let output = runSQLite(dbPath: dbPath, query: query)
        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|")
        let tokens = Int(parts.first ?? "0") ?? 0
        let threads = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        let updated = parts.count > 2 ? (TimeInterval(parts[2]) ?? 0) : 0
        let hourTokens = parts.count > 3 ? (Int(parts[3]) ?? 0) : 0
        let lastSeen = updated > 0 ? Date(timeIntervalSince1970: updated) : nil

        return AIUsageSnapshot(
            id: "codex",
            name: "Codex",
            detail: hourTokens > 0 ? "\(format(hourTokens)) diese Stunde" : "Diese Stunde ruhig",
            secondary: threads > 0 ? "\(format(tokens)) heute · \(threads) Thread(s) · \(lastSeenText(lastSeen))" : "Quelle: ~/.codex/state_5.sqlite",
            status: "Live lokal",
            symbol: "terminal",
            tint: .cyan,
            hourTokens: hourTokens,
            hourlyBudget: hourlyBudget > 0 ? hourlyBudget : nil,
            remainingPercent: remainingPercent(used: hourTokens, budget: hourlyBudget),
            limitText: hourlyBudget > 0 ? "Budget: \(format(hourlyBudget)) Tokens/Stunde" : "Restlimit nicht lokal verfügbar"
        )
    }

    nonisolated private static func runSQLite(dbPath: String, query: String) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [dbPath, query]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    nonisolated private static func format(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName))
    }

    nonisolated private static func lastSeenText(_ date: Date?) -> String {
        guard let date else { return "kein Zeitstempel" }
        return "zuletzt \(date.formatted(date: .omitted, time: .shortened))"
    }

    nonisolated private static func maxDate(_ lhs: Date?, _ rhs: Date) -> Date {
        guard let lhs else { return rhs }
        return max(lhs, rhs)
    }

    nonisolated private static func remainingPercent(used: Int, budget: Int) -> Double? {
        guard budget > 0 else { return nil }
        let remaining = max(0, budget - used)
        return min(max((Double(remaining) / Double(budget)) * 100, 0), 100)
    }
}

private extension JSONDecoder {
    func date(fromISO8601 value: String) -> Date? {
        ISO8601DateFormatter.withFractions.date(from: value)
            ?? ISO8601DateFormatter.basic.date(from: value)
    }
}

private extension ISO8601DateFormatter {
    static let withFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let basic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private extension Dictionary where Key == String, Value == Any {
    func intValue(_ key: String) -> Int {
        if let value = self[key] as? Int {
            return value
        }
        if let value = self[key] as? Double {
            return Int(value)
        }
        if let value = self[key] as? String {
            return Int(value) ?? 0
        }
        return 0
    }
}

@MainActor
final class ServerLoadMonitor: ObservableObject {
    @Published var servers: [ServerLoad] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?

    private var refreshTask: Task<Void, Never>?

    var onlineCount: Int {
        servers.filter { $0.status == "online" }.count
    }

    var averageCpu: Double? {
        let values = servers.compactMap(\.cpu)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    func start(baseURL: String, token: String) {
        refreshTask?.cancel()
        guard !token.isEmpty else { return }

        refreshTask = Task { [weak self] in
            await self?.refresh(baseURL: baseURL, token: token)

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await self?.refresh(baseURL: baseURL, token: token)
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func login(baseURL: String, email: String, password: String) async -> String? {
        guard let url = URL(string: normalizedBaseURL(baseURL) + "/api/v1/auth/token") else {
            errorMessage = "Ungültige URL"
            return nil
        }

        isLoading = true
        errorMessage = nil

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "email": email,
                "password": password,
                "device_name": "DashboardFlow Mac Menu Bar",
            ])

            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response: response, data: data)
            let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
            isLoading = false
            return decoded.token
        } catch {
            if isCancellation(error) {
                isLoading = false
                return nil
            }
            errorMessage = readable(error)
            isLoading = false
            return nil
        }
    }

    func refresh(baseURL: String, token: String) async {
        guard !token.isEmpty else {
            errorMessage = "API-Token fehlt"
            return
        }
        guard let url = URL(string: normalizedBaseURL(baseURL) + "/api/v1/servers") else {
            errorMessage = "Ungültige URL"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response: response, data: data)
            let decoded = try JSONDecoder().decode(ServerListResponse.self, from: data)
            servers = decoded.data
            lastUpdated = Date()
            isLoading = false
        } catch {
            if isCancellation(error) {
                isLoading = false
                return
            }
            errorMessage = readable(error)
            isLoading = false
        }
    }

    private func normalizedBaseURL(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "DashboardFlow", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: body,
            ])
        }
    }

    private func readable(_ error: Error) -> String {
        let message = error.localizedDescription
        if message.count > 140 {
            return String(message.prefix(140)) + "..."
        }
        return message
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}

final class WebViewModel: ObservableObject {
    let webView = WKWebView()

    init() {
        webView.allowsBackForwardNavigationGestures = true
    }

    func load(_ url: URL) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}

struct DashboardWebView: NSViewRepresentable {
    @ObservedObject var model: WebViewModel
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        model.load(url)
        return model.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        model.load(url)
    }
}

struct ContentView: View {
    @State private var route: DashboardRoute = .flowMap
    @StateObject private var webModel = WebViewModel()
    @AppStorage("baseURL") private var baseURL = "https://serverflow.careflow-pflege.de"

    private var targetURL: URL {
        let trimmedBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: trimmedBase + route.path) ?? URL(string: "https://serverflow.careflow-pflege.de/dashboard")!
    }

    var body: some View {
        NavigationSplitView {
            List(DashboardRoute.allCases, selection: $route) { item in
                Label(item.title, systemImage: item.symbol)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            if route == .flowMap {
                FlowMapView(baseURL: $baseURL, openDashboard: { route = .dashboard })
            } else {
                DashboardWebView(model: webModel, url: targetURL)
                    .overlay(alignment: .topLeading) {
                        ConnectionPill(baseURL: baseURL)
                            .padding(12)
                    }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    webModel.webView.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Zurück")

                Button {
                    webModel.webView.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help("Vor")

                Button {
                    webModel.webView.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Neu laden")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Instanz", selection: $baseURL) {
                    Text("Production").tag("https://serverflow.careflow-pflege.de")
                    Text("Lokal :8000").tag("http://127.0.0.1:8000")
                    Text("Lokal :8080").tag("http://127.0.0.1:8080")
                }
                .pickerStyle(.segmented)
                .frame(width: 300)

                Button {
                    NSWorkspace.shared.open(targetURL)
                } label: {
                    Image(systemName: "safari")
                }
                .help("Im Browser öffnen")
            }
        }
        .frame(minWidth: 1080, minHeight: 720)
    }
}

struct ConnectionPill: View {
    let baseURL: String

    var body: some View {
        Text(baseURL.contains("127.0.0.1") ? "Lokal" : "Production")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
    }
}

struct FlowMapView: View {
    @Binding var baseURL: String
    let openDashboard: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DashboardFlow")
                            .font(.system(size: 34, weight: .bold))
                        Text("Dein Infrastruktur-Dashboard als Mac-App: Monitoring, DNS, Docker, Kosten, Alerts und der visuelle Projekt-Workflow in einem Fenster.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button(action: openDashboard) {
                        Label("Dashboard öffnen", systemImage: "arrow.right.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                HStack(spacing: 10) {
                    Label(baseURL.contains("127.0.0.1") ? "Lokale Instanz" : "Production Instanz", systemImage: "network")
                    Text(baseURL)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                    ForEach(flowSteps) { step in
                        FlowStepCard(step: step)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Arbeitsfluss")
                        .font(.headline)
                    Text("Server und Dienste liefern Metriken per SSH. Docker und Health-Checks reichern die Übersicht an. Cloudflare synchronisiert DNS-Daten. Alerts, Kosten und Deployments bilden daraus den operativen Blick, und der Workflow-Editor dokumentiert die Projektstruktur visuell.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator, lineWidth: 1)
                )
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct FlowStepCard: View {
    let step: FlowStep

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: step.symbol)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(step.tint)
                    .frame(width: 34, height: 34)

                Text(step.title)
                    .font(.headline)
            }

            Text(step.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(step.tint.opacity(0.35), lineWidth: 1)
        )
    }
}

struct ServerLoadMenuView: View {
    @EnvironmentObject var monitor: ServerLoadMonitor
    @EnvironmentObject var aiMonitor: AIUsageMonitor
    @AppStorage("baseURL") private var baseURL = "https://serverflow.careflow-pflege.de"
    @AppStorage("apiEmail") private var apiEmail = ""
    @AppStorage("apiToken") private var apiToken = ""
    @StateObject private var limitWebModel = WebViewModel()
    @State private var section: MenuSection = .servers
    @State private var limitPage: LimitPage = .claude
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Label(section.title, systemImage: section.symbol)
                    .font(.headline)
                Spacer()
                if section == .servers {
                    Button {
                        Task {
                            await monitor.refresh(baseURL: baseURL, token: apiToken)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(apiToken.isEmpty || monitor.isLoading)
                    .help("Aktualisieren")
                } else {
                    Button {
                        limitWebModel.webView.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Neu laden")
                }
            }

            Picker("Ansicht", selection: $section) {
                ForEach(MenuSection.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if section == .servers {
                serverSection
            } else {
                limitsSection
            }

            Divider()

            HStack {
                if section == .servers {
                    Button("Token löschen") {
                        apiToken = ""
                        monitor.stop()
                        monitor.servers = []
                    }
                    .disabled(apiToken.isEmpty)
                } else {
                    Text("Offizielle Account-Seiten")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Beenden") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(14)
        .frame(width: section == .limits ? 780 : 400)
        .onAppear {
            if !apiToken.isEmpty {
                monitor.start(baseURL: baseURL, token: apiToken)
            }
        }
        .onChange(of: baseURL) { _, newValue in
            monitor.start(baseURL: newValue, token: apiToken)
        }
        .onChange(of: apiToken) { _, newValue in
            monitor.start(baseURL: baseURL, token: newValue)
        }
    }

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if apiToken.isEmpty {
                loginView
            } else {
                summaryView
                serverListView
            }

            if let error = monitor.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
    }

    private var limitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("Seite", selection: $limitPage) {
                    ForEach(LimitPage.allCases) { page in
                        Text(page.rawValue).tag(page)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    NSWorkspace.shared.open(limitPage.url)
                } label: {
                    Image(systemName: "safari")
                }
                .buttonStyle(.borderless)
                .help("Im Browser öffnen")
            }

            DashboardWebView(model: limitWebModel, url: limitPage.url)
                .frame(height: 560)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator, lineWidth: 1)
                )

            Text("Die App zeigt hier die Anbieter-Seiten direkt an. Sie liest daraus keine Limits aus und verändert DashboardFlow nicht.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var loginView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Einmal mit deiner ServerFlow-API anmelden.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("E-Mail", text: $apiEmail)
                .textFieldStyle(.roundedBorder)

            SecureField("Passwort", text: $password)
                .textFieldStyle(.roundedBorder)

            Button {
                Task {
                    if let token = await monitor.login(baseURL: baseURL, email: apiEmail, password: password) {
                        apiToken = token
                        password = ""
                    }
                }
            } label: {
                Label(monitor.isLoading ? "Anmelden ..." : "API-Token erstellen", systemImage: "key")
            }
            .buttonStyle(.borderedProminent)
            .disabled(apiEmail.isEmpty || password.isEmpty || monitor.isLoading)
        }
    }

    private var summaryView: some View {
        HStack(spacing: 10) {
            MetricChip(title: "Online", value: "\(monitor.onlineCount)/\(monitor.servers.count)", tint: .green)
            MetricChip(title: "CPU", value: percentText(monitor.averageCpu), tint: .blue)
            MetricChip(title: "Update", value: updateText, tint: .secondary)
        }
    }

    private var serverListView: some View {
        VStack(spacing: 8) {
            if monitor.servers.isEmpty && monitor.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if monitor.servers.isEmpty {
                Text("Noch keine Serverdaten geladen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(monitor.servers) { server in
                    ServerLoadRow(server: server)
                }
            }
        }
    }

    private var updateText: String {
        guard let lastUpdated = monitor.lastUpdated else { return "--" }
        return lastUpdated.formatted(date: .omitted, time: .shortened)
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(round(value)))%"
    }

}

struct AIUsageSnapshotRow: View {
    let snapshot: AIUsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: snapshot.symbol)
                    .foregroundStyle(snapshot.tint)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.name)
                        .font(.subheadline.weight(.semibold))

                    Text(snapshot.status)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(snapshot.tint)
                }

                Spacer()

                Text(snapshot.detail)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Rest nutzbar")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(snapshot.remainingPercent.map { "\(Int(round($0)))%" } ?? "--")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(snapshot.remainingPercent == nil ? .secondary : snapshot.tint)
                }

                ProgressView(value: snapshot.remainingPercent ?? 0, total: 100)
                    .tint(snapshot.remainingPercent == nil ? .secondary : snapshot.tint)
            }

            Text(snapshot.secondary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(snapshot.limitText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
    }
}

struct MetricChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ServerLoadRow: View {
    let server: ServerLoad

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Circle()
                    .fill(server.status == "online" ? Color.green : Color.red)
                    .frame(width: 8, height: 8)

                Text(server.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                Text(server.status)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ResourceBar(label: "CPU", value: server.cpu, tint: .blue)
            ResourceBar(label: "RAM", value: server.memoryPercent, tint: .green)
            ResourceBar(label: "Disk", value: server.diskPercent, tint: .orange)
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
    }
}

struct ResourceBar: View {
    let label: String
    let value: Double?
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)

            ProgressView(value: min(max(value ?? 0, 0), 100), total: 100)
                .tint(tint)

            Text(value.map { "\(Int(round($0)))%" } ?? "--")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }
}

@main
struct DashboardFlowMacApp: App {
    @StateObject private var monitor = ServerLoadMonitor()
    @StateObject private var aiMonitor = AIUsageMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(monitor)
                .environmentObject(aiMonitor)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            ServerLoadMenuView()
                .environmentObject(monitor)
                .environmentObject(aiMonitor)
        } label: {
            Label {
                Text("DF")
            } icon: {
                Image(systemName: monitor.errorMessage == nil ? "speedometer" : "exclamationmark.triangle")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
