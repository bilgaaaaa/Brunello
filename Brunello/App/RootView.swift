import SwiftUI

/// Chooses the screen for the current phase and keeps the diary fresh.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch appState.phase {
            case .loading:
                StatusScreen(emoji: "🐾", title: "Fetching the diary", message: nil, isLoading: true, action: nil)
            case .setupNeeded:
                StatusScreen(
                    emoji: "🛠️",
                    title: "One step left",
                    message: "Add your Supabase URL and key in AppConfig.swift, then run the app again.",
                    isLoading: false,
                    action: nil
                )
            case .failed:
                StatusScreen(
                    emoji: "📡",
                    title: "Can't reach the diary",
                    message: "Check your internet connection and try again.",
                    isLoading: false,
                    action: { Task { await appState.start() } }
                )
            case .onboarding:
                OnboardingView()
            case .ready:
                if let family = appState.family {
                    MainTabView(family: family)
                }
            }
        }
        .toast(appState.toast) { appState.clearToast($0) }
        .task { await appState.start() }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await appState.appBecameActive() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .diaryDidChange)) { _ in
            Task { await appState.refresh() }
        }
    }
}

/// The four tabs of the app.
struct MainTabView: View {
    let family: Family

    var body: some View {
        TabView {
            TodayView(family: family)
                .tabItem { Label("Today", systemImage: "pawprint.fill") }
            PhotosView(family: family)
                .tabItem { Label("Photos", systemImage: "photo.on.rectangle.angled") }
            MoneyView(family: family)
                .tabItem { Label("Money", systemImage: "eurosign.circle.fill") }
            FamilyView(family: family)
                .tabItem { Label("Family", systemImage: "heart.fill") }
        }
    }
}

/// Full-screen message used while loading or when something needs attention.
struct StatusScreen: View {
    let emoji: String
    let title: String
    let message: String?
    let isLoading: Bool
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Text(emoji).font(.system(size: 64))
            Text(title).font(.title2.bold()).foregroundStyle(Theme.ink)
            if let message {
                Text(message).font(.body).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
            }
            if isLoading {
                ProgressView()
            }
            if let action {
                Button("Try again", action: action).buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
