import AuthenticationServices
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
                    Text("You’re using Chalkbook as a guest").font(.headline)
                    Text("Sign in to join Friends.")
                        .font(.subheadline).foregroundStyle(ClimbTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
                    Button(action: openPortal) {
                        Text("Sign in or create an account").frame(maxWidth: .infinity, minHeight: 44)
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
            GeometryReader { screen in
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            AscentIcon(size: 96)
                            Text(onFinish == nil ? "Your climbing,\nyour account." : "Welcome to\nChalkbook.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                            Text("Sign in to connect with friends.").foregroundStyle(ClimbTheme.secondaryText)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if !LoginConfiguration.appleEnabled {
                            Text("Apple sign-in isn’t available in this build. You can still use Google when configured, or continue without an account.")
                                .font(.subheadline).foregroundStyle(ClimbTheme.secondaryText).accessibilityIdentifier("appleSetupMessage").fixedSize(horizontal: false, vertical: true)
                        }
                        if LoginConfiguration.googleClientID == nil {
                            Text("Google sign-in isn’t configured in this build. You can continue without an account.")
                                .font(.subheadline).foregroundStyle(ClimbTheme.secondaryText).accessibilityIdentifier("googleSetupMessage").fixedSize(horizontal: false, vertical: true)
                        }
                        VStack(spacing: 12) {
                            SignInWithAppleButton(.signIn) { request in
                                request.requestedScopes = [.fullName, .email]
                            } onCompletion: { result in
                                auth.completeApple(result)
                            }
                            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                            // The UIKit-backed button fixes its style at creation, so rebuild it when the app's forced appearance applies.
                            .id(colorScheme)
                            .frame(height: 52)
                            .clipShape(.rect(cornerRadius: 12))
                            .disabled(!LoginConfiguration.appleEnabled || auth.isBusy)
                            .accessibilityIdentifier("appleLogin")
                            // The provider buttons don't report a disabled state to VoiceOver; the setup message above explains instead.
                            .accessibilityHidden(!LoginConfiguration.appleEnabled)
                            Button {
                                guard let scene = UIApplication.shared.connectedScenes
                                    .compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
                                      var presenter = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
                                    auth.errorMessage = "The sign-in window couldn’t open. Please try again."; return
                                }
                                while let presented = presenter.presentedViewController { presenter = presented }
                                Task { await auth.signInWithGoogle(presenting: presenter) }
                            } label: {
                                HStack(spacing: 8) {
                                    Image("GoogleG").resizable().frame(width: 20, height: 20).accessibilityHidden(true)
                                    Text("Sign in with Google")
                                }
                            }
                            // Google's button colors: the SDK's own button can't match the Apple button's height or corners.
                            .buttonStyle(LoginButtonStyle(fill: .white, text: Color(red: 0.12, green: 0.12, blue: 0.12)))
                            .disabled(LoginConfiguration.googleClientID == nil || auth.isBusy)
                            .accessibilityIdentifier("googleLogin")
                            .accessibilityHidden(LoginConfiguration.googleClientID == nil)
                            if onFinish != nil {
                                Button("Continue as guest", action: finish)
                                    .buttonStyle(LoginButtonStyle(fill: Color(uiColor: .tertiarySystemFill), text: .primary))
                                    .accessibilityIdentifier("continueAsGuest")
                            }
                            if auth.isBusy { SwiftUI.ProgressView("Signing in…") }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        if let message = auth.errorMessage {
                            Text(message).font(.subheadline).foregroundStyle(ClimbTheme.error).fixedSize(horizontal: false, vertical: true)
                            Button("Dismiss message") { auth.errorMessage = nil }
                        }
                        Text("Your log stays on this iPhone.")
                            .font(.footnote).foregroundStyle(ClimbTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
                    }
                    .multilineTextAlignment(.center)
                    .padding(24)
                    .frame(minHeight: screen.size.height)
                }
            }
            .background(ClimbTheme.background)
            .navigationTitle(onFinish == nil ? "Sign in" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(onFinish == nil ? .automatic : .hidden, for: .navigationBar)
            .toolbar { if onFinish == nil { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } } }
            .onChange(of: auth.account) { _, account in if account != nil { finish() } }
        }
    }
}

/// Same size and shape as the Sign in with Apple button above it.
private struct LoginButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let fill: Color
    let text: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.medium)).foregroundStyle(text)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(fill, in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color(uiColor: .separator)) }
            .opacity(configuration.isPressed ? 0.7 : isEnabled ? 1 : 0.5)
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
