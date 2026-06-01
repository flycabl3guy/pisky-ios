import SwiftUI
import Combine

// ─── Option lists (verbatim from SettingsScreen.kt) ─────────────────────────────
private let MAP_STYLES = ["Street", "Satellite", "Hybrid", "Terrain"]
private let POLL_INTERVALS = ["Off", "15 min", "30 min", "1 hr"]
private let NOTIF_SOUNDS = ["Chime", "Silent"]

// MARK: - SettingsViewModel

/// Port of `SettingsViewModel.kt`. Pi connection edit-state mirrors `ConnectionConfig`; the
/// persisted display/notification settings read/write `container.preferences` (the UserDefaults
/// wrapper). Discovery uses `container.mdns.discover()` (8 s window like the Android `discover {}`).
@MainActor @Observable
final class SettingsViewModel {

    // Live connection
    private(set) var config: ConnectionConfig = .default
    private(set) var receiverStats: ReceiverStats?
    private(set) var connectionMode: ConnectionMode = .disconnected

    // Persisted display / notification settings
    var logDepth: Double = 2
    var pollIntervalIdx: Int = 0
    var mapStyle: String = "Street"
    var showRangeRings: Bool = true
    var showTrails: Bool = true
    var trailLength: Double = 20
    var emergencyAlerts: Bool = true
    var militaryAlerts: Bool = false
    var notifSound: String = "Chime"

    // Discovery
    private(set) var discoveredHosts: [String] = []
    private(set) var isDiscovering = false

    // Connection edit state
    var editHostname = ""
    var editPort: Int = ConnectionConfig.default.port
    var useBasicAuth = false
    var editUsername = ""
    var editPassword = ""

    // Test result
    private(set) var testResult: String?

    @ObservationIgnored private var bag = Set<AnyCancellable>()
    @ObservationIgnored private var discoveryBag = Set<AnyCancellable>()
    @ObservationIgnored private var discoveryTask: Task<Void, Never>?
    @ObservationIgnored private weak var container: AppContainer?
    private var started = false

    func start(_ c: AppContainer) {
        guard !started else { return }
        started = true; container = c

        c.connectionRepository.observeConfig()
            .receive(on: RunLoop.main)
            .sink { [weak self] cfg in
                guard let self else { return }
                self.config = cfg
                self.editHostname = cfg.hostname
                self.editPort = cfg.port
                self.useBasicAuth = cfg.useBasicAuth
                self.editUsername = cfg.username
                self.editPassword = cfg.password
            }
            .store(in: &bag)

        c.aircraftRepository.observeReceiverStats()
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.receiverStats = $0 }
            .store(in: &bag)

        c.aircraftRepository.observeConnectionMode()
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.connectionMode = $0 }
            .store(in: &bag)

        let p = c.preferences
        p.logDepth.receive(on: RunLoop.main).sink { [weak self] in self?.logDepth = Double($0) }.store(in: &bag)
        p.pollIntervalIdx.receive(on: RunLoop.main).sink { [weak self] in self?.pollIntervalIdx = $0 }.store(in: &bag)
        p.mapStyle.receive(on: RunLoop.main).sink { [weak self] in self?.mapStyle = $0 }.store(in: &bag)
        p.showRangeRings.receive(on: RunLoop.main).sink { [weak self] in self?.showRangeRings = $0 }.store(in: &bag)
        p.showTrails.receive(on: RunLoop.main).sink { [weak self] in self?.showTrails = $0 }.store(in: &bag)
        p.trailLength.receive(on: RunLoop.main).sink { [weak self] in self?.trailLength = Double($0) }.store(in: &bag)
        p.emergencyAlerts.receive(on: RunLoop.main).sink { [weak self] in self?.emergencyAlerts = $0 }.store(in: &bag)
        p.militaryAlerts.receive(on: RunLoop.main).sink { [weak self] in self?.militaryAlerts = $0 }.store(in: &bag)
        p.notifSound.receive(on: RunLoop.main).sink { [weak self] in self?.notifSound = $0 }.store(in: &bag)
    }

    // ── Persisted-setting intents ───────────────────────────────────────────
    func setLogDepth(_ v: Double)        { container?.preferences.setLogDepth(Float(v)) }
    func setPollIntervalIdx(_ v: Int)    { Task { await container?.preferences.setPollIntervalIdx(v) } }
    func setMapStyle(_ v: String)        { Task { await container?.preferences.setMapStyle(v) } }
    func setShowRangeRings(_ v: Bool)    { Task { await container?.preferences.setShowRangeRings(v) } }
    func setShowTrails(_ v: Bool)        { Task { await container?.preferences.setShowTrails(v) } }
    func setTrailLength(_ v: Double)     { container?.preferences.setTrailLength(Float(v)) }
    func setEmergencyAlerts(_ v: Bool)   { Task { await container?.preferences.setEmergencyAlerts(v) } }
    func setMilitaryAlerts(_ v: Bool)    { Task { await container?.preferences.setMilitaryAlerts(v) } }
    func setNotifSound(_ v: String)      { Task { await container?.preferences.setNotifSound(v) } }

    // ── Connection edit intents ──────────────────────────────────────────────
    func onBasicAuthToggle() { useBasicAuth.toggle() }
    func selectDiscoveredHost(_ host: String) { editHostname = host }

    /// Browse for 8 s, accumulating distinct resolved hosts — `startDiscovery()` in Kotlin.
    func startDiscovery() {
        guard let c = container else { return }
        discoveryTask?.cancel()
        discoveryBag.removeAll()
        isDiscovering = true
        discoveredHosts = []

        c.mdns.discover()
            .receive(on: RunLoop.main)
            .sink { [weak self] result in
                guard let self else { return }
                if case let .found(hostname, _) = result, !self.discoveredHosts.contains(hostname) {
                    self.discoveredHosts.append(hostname)
                }
            }
            .store(in: &discoveryBag)

        discoveryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, !Task.isCancelled else { return }
            self.isDiscovering = false
            self.discoveryBag.removeAll()
        }
    }

    func testConnection() {
        guard let c = container else { return }
        let cfg = buildConfig()
        Task {
            do {
                let rs = try await c.aircraftRepository.testConnection(config: cfg)
                let lat = rs.latitude.map { String(format: "%.4f", $0) } ?? "?"
                let lon = rs.longitude.map { String(format: "%.4f", $0) } ?? "?"
                testResult = "\u{2713} Connected — v\(rs.version), \(lat), \(lon)"
            } catch {
                testResult = "\u{2717} \(error.localizedDescription)"
            }
        }
    }

    func saveAndConnect() {
        guard let c = container else { return }
        let cfg = buildConfig()
        Task {
            await c.connectionRepository.saveConfig(cfg)
            await c.connectionRepository.setOnboarded(true)
            c.aircraftRepository.startLiveUpdates(config: cfg)
        }
    }

    func clearTestResult() { testResult = nil }

    private func buildConfig() -> ConnectionConfig {
        ConnectionConfig(
            hostname: editHostname.trimmingCharacters(in: .whitespaces),
            port: editPort,
            username: editUsername,
            password: editPassword,
            useBasicAuth: useBasicAuth
        )
    }
}

// MARK: - SettingsScreen

/// Port of `SettingsScreen.kt` — six sections on glass cards.
struct SettingsScreen: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dimens) private var dimens
    @State private var vm = SettingsViewModel()

    @State private var passwordVisible = false
    @State private var healthExpanded = false
    @State private var showClearDialog = false
    @State private var dbSizeEstimate = "~4.2 MB"

    var body: some View {
        @Bindable var vm = vm

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                Text("Settings")
                    .font(.inter(22, weight: .bold))
                    .foregroundStyle(Palette.brass)
                    .padding(.leading, 4)
                    .padding(.bottom, 20)

                // ── 1. Pi Connection ─────────────────────────────────────
                SectionHeader("Pi Connection")
                connectionStatusCard
                Spacer().frame(height: 12)
                autoDiscoverButton
                discoveredHostsList
                Spacer().frame(height: 12)
                SettingsTextField(value: $vm.editHostname,
                                  label: "Hostname / IP",
                                  placeholder: "piaware.local or 192.168.x.x")
                Spacer().frame(height: 10)
                SettingsTextField(value: Binding(
                    get: { String(vm.editPort) },
                    set: { if let n = Int($0) { vm.editPort = n } }),
                    label: "Port",
                    placeholder: "80",
                    keyboardType: .numberPad)
                Spacer().frame(height: 12)
                SettingsToggleRow(label: "Basic Authentication",
                                  checked: vm.useBasicAuth) { _ in vm.onBasicAuthToggle() }
                if vm.useBasicAuth {
                    VStack(spacing: 0) {
                        Spacer().frame(height: 10)
                        SettingsTextField(value: $vm.editUsername, label: "Username")
                        Spacer().frame(height: 10)
                        SettingsTextField(value: $vm.editPassword,
                                          label: "Password",
                                          isSecure: !passwordVisible,
                                          trailing: {
                                              Button { passwordVisible.toggle() } label: {
                                                  Image(systemName: passwordVisible ? "eye" : "eye.slash")
                                                      .foregroundStyle(Palette.textMuted)
                                              }
                                          })
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer().frame(height: 16)
                PremiumButton(action: { vm.testConnection() },
                              text: "Test Connection",
                              variant: .secondary)
                    .frame(maxWidth: .infinity)
                if let result = vm.testResult {
                    testResultCard(result)
                }
                Spacer().frame(height: 14)
                PremiumButton(action: { vm.saveAndConnect() },
                              text: "Save & Connect",
                              variant: .primary,
                              contentPaddingV: 15)
                    .frame(maxWidth: .infinity)

                Spacer().frame(height: 24)

                // ── 2. Receiver Health (collapsible) ──────────────────────
                CollapsibleSectionHeader(title: "Receiver Health",
                                         expanded: healthExpanded) {
                    healthExpanded.toggle()
                }
                if healthExpanded {
                    receiverHealthCard.transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer().frame(height: 24)

                // ── 3. Data & Logging ─────────────────────────────────────
                SectionHeader("Data & Logging")
                dataLoggingCard

                Spacer().frame(height: 24)

                // ── 4. Map & Display ──────────────────────────────────────
                SectionHeader("Map & Display")
                mapDisplayCard

                Spacer().frame(height: 24)

                // ── 5. Notifications & Alerts ─────────────────────────────
                SectionHeader("Notifications & Alerts")
                notificationsCard

                Spacer().frame(height: 24)

                // ── 6. About ──────────────────────────────────────────────
                SectionHeader("About")
                aboutCard

                Spacer().frame(height: 32)
            }
            .padding(.horizontal, dimens.screenPadding)
            .padding(.vertical, dimens.screenPadding)
        }
        .background(Palette.background.ignoresSafeArea())
        .animation(.easeInOut, value: vm.useBasicAuth)
        .animation(.easeInOut, value: healthExpanded)
        .animation(.easeInOut, value: vm.testResult)
        .animation(.easeInOut, value: vm.discoveredHosts)
        .animation(.easeInOut, value: vm.showTrails)
        .task { vm.start(container) }
        .alert("Clear History", isPresented: $showClearDialog) {
            Button("Clear", role: .destructive) {
                dbSizeEstimate = "0 MB"
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all stored aircraft history and logs. This cannot be undone.")
        }
    }

    // ── Connection status ────────────────────────────────────────────────
    private var dotColor: Color {
        switch vm.connectionMode {
        case .pollingHttp, .websocket: return Palette.statusOk
        case .connecting:              return Palette.statusWarn
        default:                       return Palette.statusError
        }
    }

    private var connectionStatusCard: some View {
        SettingsCard {
            HStack(spacing: 10) {
                Circle().fill(dotColor).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(vm.config.hostname):\(vm.config.port)")
                        .font(.inter(14, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Text(vm.connectionMode.label)
                        .font(.inter(12))
                        .foregroundStyle(dotColor)
                }
                Spacer()
            }
        }
    }

    private var autoDiscoverButton: some View {
        Button {
            vm.startDiscovery()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.cyan)
                    .rotationEffect(.degrees(vm.isDiscovering ? 360 : 0))
                    .animation(vm.isDiscovering
                               ? .linear(duration: 1.2).repeatForever(autoreverses: false)
                               : .default, value: vm.isDiscovering)
                Text(vm.isDiscovering ? "Scanning…" : "Auto-Discover Pi")
                    .font(.inter(14, weight: .medium))
                    .foregroundStyle(Palette.cyan)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.cyan.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(vm.isDiscovering)
    }

    @ViewBuilder private var discoveredHostsList: some View {
        if !vm.discoveredHosts.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(vm.discoveredHosts, id: \.self) { host in
                    Button { vm.selectDiscoveredHost(host) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "wifi")
                                .font(.system(size: 14))
                                .foregroundStyle(Palette.statusOk)
                            Text(host)
                                .font(.inter(13))
                                .foregroundStyle(Palette.statusOk)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func testResultCard(_ result: String) -> some View {
        let color = result.hasPrefix("\u{2713}") ? Palette.statusOk : Palette.statusError
        return SettingsCard(topPadding: 10) {
            HStack {
                Text(result)
                    .font(.inter(13))
                    .foregroundStyle(color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Dismiss") { vm.clearTestResult() }
                    .font(.inter(12))
                    .foregroundStyle(Palette.textMuted)
            }
        }
    }

    // ── Receiver Health ────────────────────────────────────────────────────
    private var receiverHealthCard: some View {
        SettingsCard {
            if let rs = vm.receiverStats {
                VStack(spacing: 8) {
                    if let antenna = rs.antenna { HealthRow("Antenna", antenna) }
                    let lat = rs.latitude.map { String(format: "%.5f", $0) } ?? "—"
                    let lon = rs.longitude.map { String(format: "%.5f", $0) } ?? "—"
                    HealthRow("Location", "\(lat), \(lon)")
                    HealthRow("Refresh", "\(rs.refreshIntervalMs) ms")
                    HealthRow("Version", rs.version)
                    Spacer().frame(height: 4)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Signal Strength")
                            .font(.inter(12))
                            .foregroundStyle(Palette.textSecondary)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Palette.cardElevated)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Palette.statusOk)
                                    .frame(width: geo.size.width * 0.65)
                            }
                        }
                        .frame(height: 6)
                    }
                }
            } else {
                Text("No receiver data — connect to fetch stats.")
                    .font(.inter(13))
                    .foregroundStyle(Palette.textMuted)
            }
        }
    }

    // ── Data & Logging ───────────────────────────────────────────────────
    private var dataLoggingCard: some View {
        @Bindable var vm = vm
        return SettingsCard {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Daily log depth")
                            .font(.inter(13)).foregroundStyle(Palette.textSecondary)
                        Spacer()
                        Text("\(Int(vm.logDepth)) days")
                            .font(.inter(13, weight: .semibold)).foregroundStyle(Palette.brass)
                    }
                    Slider(value: Binding(get: { vm.logDepth },
                                          set: { vm.logDepth = $0; vm.setLogDepth($0) }),
                           in: 1...7, step: 1)
                        .tint(Palette.brass)
                }

                Divider().overlay(Palette.outline.opacity(0.5))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Background polling interval")
                        .font(.inter(13)).foregroundStyle(Palette.textSecondary)
                    PillRow(options: POLL_INTERVALS,
                            selectedIndex: vm.pollIntervalIdx,
                            accent: Palette.cyan) { vm.setPollIntervalIdx($0) }
                }

                Divider().overlay(Palette.outline.opacity(0.5))

                HStack {
                    Text("Database size")
                        .font(.inter(13)).foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Text(dbSizeEstimate)
                        .font(.inter(13)).foregroundStyle(Palette.textMuted)
                }

                Divider().overlay(Palette.outline.opacity(0.5))

                PremiumButton(action: { showClearDialog = true },
                              text: "Clear History",
                              variant: .danger)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // ── Map & Display ──────────────────────────────────────────────────────
    private var mapDisplayCard: some View {
        @Bindable var vm = vm
        return SettingsCard {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Map style")
                        .font(.inter(13)).foregroundStyle(Palette.textSecondary)
                    PillRow(options: MAP_STYLES,
                            selectedIndex: MAP_STYLES.firstIndex(of: vm.mapStyle) ?? 0,
                            accent: Palette.brass) { vm.setMapStyle(MAP_STYLES[$0]) }
                }
                Divider().overlay(Palette.outline.opacity(0.5))
                SettingsToggleRow(label: "Show range rings", checked: vm.showRangeRings) {
                    vm.setShowRangeRings($0)
                }
                Divider().overlay(Palette.outline.opacity(0.5))
                SettingsToggleRow(label: "Show aircraft trails", checked: vm.showTrails) {
                    vm.setShowTrails($0)
                }
                if vm.showTrails {
                    VStack(alignment: .leading, spacing: 6) {
                        Spacer().frame(height: 4)
                        HStack {
                            Text("Trail length")
                                .font(.inter(13)).foregroundStyle(Palette.textSecondary)
                            Spacer()
                            Text("\(Int(vm.trailLength)) points")
                                .font(.inter(13, weight: .semibold)).foregroundStyle(Palette.brass)
                        }
                        Slider(value: Binding(get: { vm.trailLength },
                                              set: { vm.trailLength = $0; vm.setTrailLength($0) }),
                               in: 5...50, step: 5)
                            .tint(Palette.brass)
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    // ── Notifications & Alerts ─────────────────────────────────────────────
    private var notificationsCard: some View {
        SettingsCard {
            VStack(spacing: 16) {
                SettingsToggleRow(label: "Emergency squawk alerts",
                                  checked: vm.emergencyAlerts,
                                  accent: Palette.statusError) { vm.setEmergencyAlerts($0) }
                Divider().overlay(Palette.outline.opacity(0.5))
                SettingsToggleRow(label: "Military aircraft alerts",
                                  checked: vm.militaryAlerts,
                                  accent: Palette.brassBright) { vm.setMilitaryAlerts($0) }
                Divider().overlay(Palette.outline.opacity(0.5))
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notification sound")
                        .font(.inter(13)).foregroundStyle(Palette.textSecondary)
                    PillRow(options: NOTIF_SOUNDS,
                            selectedIndex: NOTIF_SOUNDS.firstIndex(of: vm.notifSound) ?? 0,
                            accent: Palette.cyan) { vm.setNotifSound(NOTIF_SOUNDS[$0]) }
                }
            }
        }
    }

    // ── About ────────────────────────────────────────────────────────────
    private var aboutCard: some View {
        SettingsCard {
            VStack(spacing: 12) {
                AboutRow("Version", "PiSky Platinum v3.1")
                Divider().overlay(Palette.outline.opacity(0.5))
                AboutRow("Pi IP", vm.config.hostname.isEmpty ? "192.168.1.207" : vm.config.hostname)
                Divider().overlay(Palette.outline.opacity(0.5))
                AboutRow("Source", "github.com/piaware-android")
            }
        }
    }
}

// MARK: - Reusable sub-views

private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.inter(13, weight: .semibold))
            .tracking(1)
            .foregroundStyle(Palette.brass)
            .padding(.leading, 4)
            .padding(.bottom, 10)
    }
}

private struct CollapsibleSectionHeader: View {
    let title: String
    let expanded: Bool
    let onToggle: () -> Void
    var body: some View {
        Button(action: onToggle) {
            HStack {
                Text(title)
                    .font(.inter(13, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(Palette.brass)
                Spacer()
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.brass)
            }
            .padding(.leading, 4)
            .padding(.bottom, 10)
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsCard<Content: View>: View {
    var topPadding: CGFloat = 0
    @ViewBuilder var content: () -> Content
    init(topPadding: CGFloat = 0, @ViewBuilder content: @escaping () -> Content) {
        self.topPadding = topPadding
        self.content = content
    }
    var body: some View {
        VStack(alignment: .leading) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Palette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Palette.glassBorder, lineWidth: 1)
            )
            .padding(.top, topPadding)
    }
}

private struct SettingsToggleRow: View {
    let label: String
    let checked: Bool
    var accent: Color = Palette.cyan
    let onChange: (Bool) -> Void
    var body: some View {
        Toggle(isOn: Binding(get: { checked }, set: { HangarHaptics.toggle(); onChange($0) })) {
            Text(label)
                .font(.inter(14))
                .foregroundStyle(Palette.textSecondary)
        }
        .tint(accent)
    }
}

private struct SettingsTextField<Trailing: View>: View {
    @Binding var value: String
    let label: String
    var placeholder: String = ""
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false
    @ViewBuilder var trailing: () -> Trailing

    @FocusState private var focused: Bool

    init(value: Binding<String>,
         label: String,
         placeholder: String = "",
         keyboardType: UIKeyboardType = .default,
         isSecure: Bool = false,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self._value = value
        self.label = label
        self.placeholder = placeholder
        self.keyboardType = keyboardType
        self.isSecure = isSecure
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.inter(12))
                .foregroundStyle(focused ? Palette.cyan : Palette.textMuted)
            HStack {
                Group {
                    if isSecure { SecureField(placeholder, text: $value) }
                    else { TextField(placeholder, text: $value) }
                }
                .focused($focused)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.inter(15))
                .foregroundStyle(Palette.textPrimary)
                .tint(Palette.cyan)
                trailing()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Palette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(focused ? Palette.cyan : Palette.outline, lineWidth: 1)
            )
        }
        .animation(.easeInOut(duration: 0.15), value: focused)
    }
}

/// Row of rounded selectable pills — the Compose `Box`/`clickable` chip groups.
private struct PillRow: View {
    let options: [String]
    let selectedIndex: Int
    var accent: Color = Palette.cyan
    let onSelect: (Int) -> Void
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.offset) { idx, label in
                let selected = idx == selectedIndex
                Button { HangarHaptics.select(); onSelect(idx) } label: {
                    Text(label)
                        .font(.inter(12))
                        .foregroundStyle(selected ? accent : Palette.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selected ? accent.opacity(0.2) : Palette.cardElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(selected ? accent : Palette.outline, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct HealthRow: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
    var body: some View {
        HStack {
            Text(label).font(.inter(13)).foregroundStyle(Palette.textSecondary)
            Spacer()
            Text(value).font(.inter(13, weight: .medium)).foregroundStyle(Palette.textPrimary)
        }
    }
}

private struct AboutRow: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
    var body: some View {
        HStack {
            Text(label).font(.inter(13)).foregroundStyle(Palette.textSecondary)
            Spacer()
            Text(value).font(.inter(13, weight: .medium)).foregroundStyle(Palette.textPrimary)
        }
    }
}
