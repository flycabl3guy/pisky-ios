import SwiftUI
import Combine

/// Result of an mDNS browse — `DiscoveryResult` in `MdnsDiscovery.kt`. Lives in the Settings
/// feature (it did on Android too). The Data-layer `MdnsDiscovery` (NWBrowser) emits these on
/// the publisher returned by `discover()`.
enum DiscoveryResult: Equatable, Sendable {
    case searching
    case found(hostname: String, port: Int)
    case error(message: String)
}

// MARK: - ConnectionUiState / form

/// Connection test lifecycle — `ConnectionUiState` in `ConnectionViewModel.kt`.
enum ConnectionUiState: Equatable {
    case idle
    case testing
    case success(version: String)
    case error(message: String)
}

/// Mirrors the manual-entry form — `ConnectionFormState` in `ConnectionViewModel.kt`.
struct ConnectionFormState: Equatable {
    var hostname: String = ConnectionConfig.default.hostname
    var port: String = String(ConnectionConfig.default.port)
    var username: String = ""
    var password: String = ""
    var useBasicAuth: Bool = false
    var hostnameError: String? = nil
    var portError: String? = nil
}

// MARK: - ConnectionViewModel

/// Port of `ConnectionViewModel.kt`. The Fire-TV / leanback auto-onboard branch is dropped
/// (PORTING_NOTES §3 — no D-pad / tvOS target in scope).
@MainActor @Observable
final class ConnectionViewModel {

    private(set) var uiState: ConnectionUiState = .idle
    var form = ConnectionFormState()
    private(set) var discovery: DiscoveryResult = .searching

    @ObservationIgnored private var bag = Set<AnyCancellable>()
    @ObservationIgnored private weak var container: AppContainer?
    private var started = false

    func start(_ c: AppContainer) {
        guard !started else { return }
        started = true; container = c
        Task {
            let saved = await c.connectionRepository.getConfig()
            form = ConnectionFormState(
                hostname: saved.hostname,
                port: String(saved.port),
                username: saved.username,
                password: saved.password,
                useBasicAuth: saved.useBasicAuth
            )
        }
    }

    func onBasicAuthToggle(_ value: Bool) { form.useBasicAuth = value }

    /// Validate host + port (1…65535), test, persist + onboard on success — `connect()` in Kotlin.
    func connect() {
        guard let c = container else { return }

        let host = form.hostname.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { form.hostnameError = "Required"; return }
        guard let port = Int(form.port), (1...65535).contains(port) else {
            form.portError = "1–65535"; return
        }
        form.hostnameError = nil
        form.portError = nil

        let config = ConnectionConfig(
            hostname: host,
            port: port,
            username: form.username.trimmingCharacters(in: .whitespaces),
            password: form.password,
            useBasicAuth: form.useBasicAuth
        )

        uiState = .testing
        Task {
            do {
                let receiver = try await c.aircraftRepository.testConnection(config: config)
                await c.connectionRepository.saveConfig(config)
                await c.connectionRepository.setOnboarded(true)
                uiState = .success(version: receiver.version)
            } catch {
                uiState = .error(message: error.localizedDescription)
            }
        }
    }

    /// Browse the local network — `startDiscovery()` in Kotlin. On a `Found` hit, populate the form.
    func startDiscovery() {
        guard let c = container else { return }
        c.mdns.discover()
            .receive(on: RunLoop.main)
            .sink { [weak self] result in
                guard let self else { return }
                self.discovery = result
                if case let .found(hostname, port) = result {
                    self.form.hostname = hostname
                    self.form.port = String(port)
                }
            }
            .store(in: &bag)
    }
}

// MARK: - OnboardingScreen

/// Port of `OnboardingScreen.kt` — v6 Hangar Luxe. Centered glass console: live `BrandLogo`,
/// PI|SKY wordmark, auto-discover plate, manual host/port + animated basic-auth, brass Connect.
struct OnboardingScreen: View {
    let onConnected: () -> Void

    @Environment(AppContainer.self) private var container
    @State private var vm = ConnectionViewModel()
    @State private var passwordVisible = false
    @State private var entered = false

    var body: some View {
        @Bindable var vm = vm

        ZStack {
            Palette.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // ── Brand block ───────────────────────────────────────
                    BrandLogo(size: 96, animate: true)
                    Spacer().frame(height: 18)
                    HStack(spacing: 0) {
                        Text("PI")
                            .font(.rajdhani(44, weight: .bold))
                            .tracking(2.4)
                            .foregroundStyle(Palette.textPrimary)
                        Text("SKY")
                            .font(.rajdhani(44, weight: .bold))
                            .tracking(2.4)
                            .foregroundStyle(Palette.brassBright)
                    }
                    Spacer().frame(height: 6)
                    Text("LIVE ADS-B FROM YOUR PI")
                        .font(.psMono(11, weight: .medium))
                        .tracking(3.2)
                        .foregroundStyle(Palette.textMuted)

                    Spacer().frame(height: 36)

                    autoDiscoverPlate

                    if case let .found(hostname, _) = vm.discovery {
                        HStack(spacing: 6) {
                            Image(systemName: "wifi")
                                .font(.system(size: 16))
                                .foregroundStyle(Palette.statusOk)
                            Text("Found \(hostname)")
                                .font(.inter(12))
                                .foregroundStyle(Palette.statusOk)
                        }
                        .padding(.top, 8)
                        .transition(.opacity)
                    }

                    Spacer().frame(height: 24)
                    DividerLabel(text: "OR ENTER MANUALLY")
                    Spacer().frame(height: 20)

                    formPlate

                    Spacer().frame(height: 28)

                    if case let .error(message) = vm.uiState {
                        Text(message)
                            .font(.psMono(12))
                            .tracking(0.8)
                            .foregroundStyle(Palette.statusError)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 16)
                            .transition(.opacity)
                    }

                    if vm.uiState == .testing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Palette.brassBright)
                            .frame(maxWidth: .infinity, minHeight: 56)
                    } else {
                        PremiumButton(
                            action: { HangarHaptics.select(); vm.connect() },
                            text: "CONNECT",
                            variant: .primary,
                            contentPaddingV: 18,
                            cornerRadius: HangarLuxe.Radius.medium
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                .opacity(entered ? 1 : 0)
                .offset(y: entered ? 0 : 40)
            }
        }
        .animation(HangarLuxe.Motion.emphasized(HangarLuxe.Motion.duration.cinematic), value: entered)
        .animation(.easeInOut, value: vm.discovery)
        .animation(.easeInOut, value: vm.uiState)
        .animation(.easeInOut, value: vm.form.useBasicAuth)
        .task {
            vm.start(container)
            entered = true
        }
        .onChange(of: vm.uiState) { _, state in
            if case .success = state {
                HangarHaptics.select()
                onConnected()
            }
        }
    }

    // ── Auto-discover plate ────────────────────────────────────────────────
    private var autoDiscoverPlate: some View {
        VStack(spacing: 4) {
            HangarPlate(radius: HangarLuxe.Radius.medium,
                        elevation: HangarLuxe.Elevation.plate,
                        tint: Palette.cyan,
                        contentPadding: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18))
                        .foregroundStyle(Palette.cyan)
                    Text("AUTO-DISCOVER RECEIVER")
                        .font(.psMono(13, weight: .bold))
                        .tracking(2.0)
                        .foregroundStyle(Palette.cyan)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }

            Button {
                HangarHaptics.tap()
                vm.startDiscovery()
            } label: {
                Text("tap to scan local network")
                    .font(.psMono(11))
                    .tracking(1.2)
                    .foregroundStyle(Palette.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
    }

    // ── Form plate ─────────────────────────────────────────────────────────
    private var formPlate: some View {
        @Bindable var vm = vm
        return HangarPlate(radius: HangarLuxe.Radius.large,
                           elevation: HangarLuxe.Elevation.raised,
                           contentPadding: 18) {
            VStack(spacing: 0) {
                HangarField(value: $vm.form.hostname,
                            label: "HOSTNAME OR IP",
                            placeholder: "piaware.local or 192.168.1.x",
                            error: vm.form.hostnameError)
                Spacer().frame(height: 12)
                HangarField(value: $vm.form.port,
                            label: "PORT",
                            placeholder: "8088",
                            error: vm.form.portError,
                            keyboardType: .numberPad)
                Spacer().frame(height: 16)

                HStack {
                    Text("BASIC AUTHENTICATION")
                        .font(.psMono(11, weight: .medium))
                        .tracking(1.6)
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { vm.form.useBasicAuth },
                        set: { HangarHaptics.toggle(); vm.onBasicAuthToggle($0) }
                    ))
                    .labelsHidden()
                    .tint(Palette.brass)
                }

                if vm.form.useBasicAuth {
                    VStack(spacing: 0) {
                        Spacer().frame(height: 12)
                        HangarField(value: $vm.form.username, label: "USERNAME")
                        Spacer().frame(height: 12)
                        HangarField(value: $vm.form.password,
                                    label: "PASSWORD",
                                    isSecure: !passwordVisible,
                                    keyboardType: .default,
                                    trailing: {
                                        Button {
                                            HangarHaptics.tap()
                                            passwordVisible.toggle()
                                        } label: {
                                            Image(systemName: passwordVisible ? "eye" : "eye.slash")
                                                .foregroundStyle(Palette.textMuted)
                                        }
                                    })
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }
}

// MARK: - Sub-views

/// "—— OR ENTER MANUALLY ——" rule — `DividerLabel` in Kotlin.
private struct DividerLabel: View {
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Palette.outline).frame(height: 1).frame(maxWidth: .infinity)
            Text(text)
                .font(.psMono(10, weight: .bold))
                .tracking(3.0)
                .foregroundStyle(Palette.textMuted)
                .fixedSize()
            Rectangle().fill(Palette.outline).frame(height: 1).frame(maxWidth: .infinity)
        }
    }
}

/// Brass-bordered outlined field — `HangarField` in Kotlin.
private struct HangarField<Trailing: View>: View {
    @Binding var value: String
    let label: String
    var placeholder: String = ""
    var error: String? = nil
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    @ViewBuilder var trailing: () -> Trailing

    @FocusState private var focused: Bool

    init(value: Binding<String>,
         label: String,
         placeholder: String = "",
         error: String? = nil,
         isSecure: Bool = false,
         keyboardType: UIKeyboardType = .default,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self._value = value
        self.label = label
        self.placeholder = placeholder
        self.error = error
        self.isSecure = isSecure
        self.keyboardType = keyboardType
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.psMono(11, weight: .medium))
                .tracking(1.6)
                .foregroundStyle(focused ? Palette.brassBright : Palette.textMuted)
            HStack {
                Group {
                    if isSecure {
                        SecureField(placeholder, text: $value)
                    } else {
                        TextField(placeholder, text: $value)
                    }
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
            .background(Palette.background.opacity(focused ? 0.35 : 0.25))
            .clipShape(RoundedRectangle(cornerRadius: HangarLuxe.Radius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HangarLuxe.Radius.small, style: .continuous)
                    .strokeBorder(
                        error != nil ? Palette.statusError :
                            (focused ? Palette.brassBright : Palette.outline),
                        lineWidth: 1)
            )
            if let error {
                Text(error)
                    .font(.psMono(11))
                    .foregroundStyle(Palette.statusError)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: focused)
    }
}
