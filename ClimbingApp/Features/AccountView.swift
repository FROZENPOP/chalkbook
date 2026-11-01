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
                VStack(alignment: .leading, spacing: 12) {
                    Text("You’re using Climb Log as a guest").font(.headline)
                    Text("Sign in with Apple or Google to join Friends and share the sessions you choose. Your guest log stays on this iPhone.")
                        .font(.subheadline).foregroundStyle(ClimbTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
                    Button(action: openPortal) {
                        Label("Sign in or create an account", systemImage: "person.crop.circle").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent).accessibilityIdentifier("openLogin")
                }.padding(.vertical, 4)
            }
        }
    }
}

struct LoginPortalView: View {
    @Environment(AccountSession.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    /// Set for the first-launch welcome, which replaces the app instead of being presented over it.
    var onFinish: (() -> Void)? = nil
    private func finish() { if let onFinish { onFinish() } else { dismiss() } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "chevron.up.2").font(.system(size: 50, weight: .bold)).accessibilityHidden(true).foregroundStyle(ClimbTheme.accent)
                    Text(onFinish == nil ? "Your climbing,\nyour account." : "Welcome to\nClimb Log.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Sign in with your existing Apple or Google account to connect with friends. No new password to remember.").foregroundStyle(ClimbTheme.secondaryText)
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
                        // The UIKit-backed button fixes its style at creation, so rebuild it when the app's forced appearance applies.
                        .id(colorScheme)
                        .frame(height: 52)
                        .disabled(!LoginConfiguration.appleEnabled || auth.isBusy)
                        .accessibilityIdentifier("appleLogin")
                        // The provider buttons don't report a disabled state to VoiceOver; the setup message above explains instead.
                        .accessibilityHidden(!LoginConfiguration.appleEnabled)
                        GoogleSignInButton(scheme: colorScheme == .dark ? .dark : .light, style: .wide) {
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
                        .accessibilityHidden(LoginConfiguration.googleClientID == nil)
                        if auth.isBusy { SwiftUI.ProgressView("Signing in…") }
                    }
                    if let message = auth.errorMessage {
                        Text(message).font(.subheadline).foregroundStyle(ClimbTheme.error)
                        Button("Dismiss message") { auth.errorMessage = nil }
                    }
                    Text("Your log and route media stay on this iPhone. Sign-in doesn’t turn on cloud sync. Your guest log remains separate; use backup and restore to move it into your account.")
                        .font(.footnote).foregroundStyle(ClimbTheme.secondaryText)
                    Button(onFinish == nil ? "Continue without an account" : "Continue as guest", action: finish)
                        .buttonStyle(.bordered).tint(.primary).frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("continueAsGuest")
                }.padding(24)
            }
            .background(ClimbTheme.background)
            .navigationTitle(onFinish == nil ? "Sign in" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { if onFinish == nil { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } } }
            .onChange(of: auth.account) { _, account in if account != nil { finish() } }
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
        .id(colorScheme)
        .frame(height: 50)
        .accessibilityIdentifier("appleConfirm")
    }
}
