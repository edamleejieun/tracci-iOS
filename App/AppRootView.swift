import SwiftUI

struct AppRootView: View {
    @Environment(AuthSession.self) private var authSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let dependencies: AppDependencies

    @State private var pendingJoinCode: String?
    @State private var showingJoinTrip = false
    @State private var joinResult: JoinInvitationResponse?

    var body: some View {
        ZStack {
            if authSession.isLoading && !authSession.hasCompletedInitialRestore {
                LoadingView(message: "正在恢复登录状态")
            } else if authSession.isAuthenticated {
                MainTabView(dependencies: dependencies.mainScene)
                .transition(.opacity)
            } else {
                AuthLandingView(
                    authService: dependencies.mainScene.authService,
                    phoneAuthProvider: dependencies.phoneAuthProvider
                )
                    .transition(.opacity)
            }
        }
        // Cross-fade from the launch-matched LoadingView into the main scene / auth
        // landing instead of an abrupt swap.
        .animation(
            AppMotion.animation(AppMotion.normal, reduceMotion: reduceMotion),
            value: authSession.hasCompletedInitialRestore
        )
        .openTracciLinksInApp()
        .task {
            await authSession.restoreSession()
            // Check for pending deep link code after auth restore
            checkPendingInviteCode()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tracciDeepLinkJoinTrip)) { notification in
            if let code = notification.object as? String {
                handleInviteCode(code)
            }
        }
        .onChange(of: showingJoinTrip) { _, isShowing in
            if !isShowing {
                clearPendingJoinTripState()
            }
        }
        .fullScreenCover(isPresented: $showingJoinTrip) {
            JoinTripView(
                collaborationService: dependencies.mainScene.collaborationService,
                initialCode: pendingJoinCode ?? "",
                onCancel: { showingJoinTrip = false }
            ) { result in
                joinResult = result
                showingJoinTrip = false
            }
        }
        .tracciToast(
            Binding(
                get: {
                    joinResult.map {
                        TracciToastMessage.success(
                            "你已成功加入旅程，角色：\(TripMemberRole(rawValue: $0.role)?.label ?? $0.role)"
                        )
                    }
                },
                set: { newValue in
                    if newValue == nil { joinResult = nil }
                }
            ),
            bottomPadding: 28
        )
    }

    private func clearPendingJoinTripState() {
        AppDelegate.pendingInviteCode = nil
        pendingJoinCode = nil
    }

    private func checkPendingInviteCode() {
        if let code = AppDelegate.pendingInviteCode {
            handleInviteCode(code)
        }
    }

    private func handleInviteCode(_ code: String) {
        let normalized = TripInviteCode.sanitizedInput(code)
        guard authSession.isAuthenticated else {
            // Store for later — will be checked after login
            pendingJoinCode = normalized
            AppDelegate.pendingInviteCode = normalized
            return
        }
        pendingJoinCode = normalized
        showingJoinTrip = true
    }
}
