import AuthenticationServices
import GoogleSignInSwift
import SwiftUI

struct AccountSection: View {
    @Environment(AccountSession.self) private var auth
    @Environment(ProfileStore.self) private var profiles
    let openPortal: () -> Void
    let editProfile: () -> Void

    var body: some View {
        Section(header: Text("Your profile").foregroundStyle(ClimbTheme.secondaryText).font(.subheadline).fixedSize(horizontal: false, vertical: true)) {
            HStack(spacing: 16) {
                ProfileAvatar(photo: profiles.profile?.photo)
                VStack(alignment: .leading, spacing: 6) {
                    Text(profiles.profile?.name ?? auth.account?.name ?? "Your climbing profile").font(.headline).accessibilityIdentifier("profileDisplayName")
                    if let bio = profiles.profile?.bio, !bio.isEmpty { Text(bio).font(.subheadline).foregroundStyle(ClimbTheme.secondaryText) }
                    if let email = auth.account?.email { Text(email).font(.subheadline).foregroundStyle(ClimbTheme.secondaryText) }
                }
            }.padding(.vertical, 8)
            Button(profiles.profile == nil || profiles.profile?.setupComplete == false ? "Set up profile" : "Edit profile", systemImage: "person.crop.circle.badge.pencil", action: editProfile)
                .frame(minHeight: 44).disabled(profiles.errorMessage != nil).accessibilityIdentifier("editProfile")
            if let message = profiles.errorMessage {
                Text(message).foregroundStyle(ClimbTheme.error)
                Button("Retry opening profile") { profiles.retryLoading() }
            }
            if let message = auth.errorMessage {
                Text(message).font(.subheadline).foregroundStyle(ClimbTheme.error)
                Button("Dismiss account message") { auth.errorMessage = nil }
            }
            if let account = auth.account {
                Text("Signed in with \(account.provider == .apple ? "Apple" : "Google")").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
            } else {
                Button(action: openPortal) {
                    HStack { Image(systemName: "person.crop.circle").accessibilityHidden(true); Text("Sign in or create an account").fixedSize(horizontal: false, vertical: true) }.frame(minHeight: 44)
                }.accessibilityIdentifier("openLogin")
                Text("You’re logging on this device without an account.").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
            }
        }
    }
}

struct LoginPortalView: View {
    @Environment(AccountSession.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "figure.climbing").font(.system(size: 50)).foregroundStyle(ClimbTheme.forest)
                    Text("Your climbing,\nyour account.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Sign in with your existing Apple or Google account. No new password to remember.").foregroundStyle(ClimbTheme.secondaryText)
                    if !LoginConfiguration.appleEnabled {
                        Text("Apple sign-in isn’t available in this build. You can still use Google when configured, or continue without an account.")
                            .font(.subheadline).foregroundStyle(ClimbTheme.secondaryText).accessibilityIdentifier("appleSetupMessage")
                    }
                    if LoginConfiguration.googleClientID == nil {
                        Text("Google sign-in isn’t configured in this build. You can continue without an account.")
                            .font(.subheadline).foregroundStyle(ClimbTheme.secondaryText).accessibilityIdentifier("googleSetupMessage")
                    }
                    VStack(spacing: 14) {
                        SignInWithAppleButton(.signIn) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            auth.completeApple(result)
                        }
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: 52)
                        .disabled(!LoginConfiguration.appleEnabled || auth.isBusy)
                        .accessibilityIdentifier("appleLogin")
                        GoogleSignInButton {
                            guard let scene = UIApplication.shared.connectedScenes
                                .compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
                                  var presenter = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
                                auth.errorMessage = "The sign-in window couldn’t open. Please try again."; return
                            }
                            while let presented = presenter.presentedViewController { presenter = presented }
                            Task { await auth.signInWithGoogle(presenting: presenter) }
                        }
                        .frame(height: 52)
                        .disabled(LoginConfiguration.googleClientID == nil || auth.isBusy)
                        .accessibilityIdentifier("googleLogin")
                        if auth.isBusy { SwiftUI.ProgressView("Signing in…") }
                    }
                    if let message = auth.errorMessage {
                        Text(message).font(.subheadline).foregroundStyle(ClimbTheme.error)
                        Button("Dismiss message") { auth.errorMessage = nil }
                    }
                    Text("Your log and route media stay on this iPhone. Sign-in doesn’t turn on cloud sync. Your guest log remains separate; use backup and restore to move it into your account.")
                        .font(.footnote).foregroundStyle(ClimbTheme.secondaryText)
                    Button("Continue without an account") { dismiss() }.frame(maxWidth: .infinity, minHeight: 44)
                }.padding(24)
            }
            .background(ClimbTheme.background)
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onChange(of: auth.account) { _, account in if account != nil { dismiss() } }
        }
    }
}

/// Asks Apple to confirm the signed-in Apple ID again, for server actions that need a fresh identity token.
struct AppleConfirmButton: View {
    @Environment(AccountSession.self) private var auth
    @Environment(\.colorScheme) private var colorScheme
    let confirmed: () async -> Void
    var body: some View {
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = []
        } onCompletion: { result in
            auth.completeApple(result)
            if case .success = result { Task { await confirmed() } }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 50)
        .accessibilityIdentifier("appleConfirm")
    }
}
