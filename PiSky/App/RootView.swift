import SwiftUI

/// Decides between onboarding and the main app, and picks the responsive dimension set from the
/// horizontal size class (regular = iPad/landscape → tablet metrics, like the Android Tab S4 path).
struct RootView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var onboarded: Bool?

    var body: some View {
        Group {
            switch onboarded {
            case .none:
                ZStack {
                    Palette.background.ignoresSafeArea()
                    BrandLogo(size: 96)
                }
            case .some(false):
                OnboardingScreen(onConnected: { onboarded = true })
            case .some(true):
                AppNavigation()
            }
        }
        .dimens(hSize == .regular ? .tablet : .phone)
        .task {
            onboarded = await container.connectionRepository.isOnboarded()
        }
    }
}
