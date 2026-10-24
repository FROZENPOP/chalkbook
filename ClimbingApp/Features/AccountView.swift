import AuthenticationServices
import GoogleSignInSwift
import SwiftUI

struct AccountSection: View {
    @Environment(AccountSession.self) private var auth
    let openPortal: () -> Void
    let requestSignOut: () -> Void

    var body: some View {
        Section("Account") {
            if let message = auth.errorMessage {
                Text(message).font(.subheadline).foregroundStyle(.red)
                Button("Dismiss account message") { auth.errorMessage = nil }
            }
            if let account = auth.account {
                Label(account.name, systemImage: "person.crop.circle.fill").font(.headline)
                if let email = account.email { Text(email).font(.subheadline).foregroundStyle(.secondary) }
                Text("Signed in with \(account.provider == .apple ? "Apple" : "Google")").font(.caption).foregroundStyle(.secondary)
                Button("Sign out", role: .destructive, action: requestSignOut).accessibilityIdentifier("signOut")
            } else {
                Button(action: openPortal) {
                    Label("Sign in or create an account", systemImage: "person.crop.circle")
                }.accessibilityIdentifier("openLogin")
                Text("You’re logging on this device without an account.").font(.caption).foregroundStyle(.secondary)
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
                    Text("Sign in with your existing Apple or Google account. No new password to remember.").foregroundStyle(.secondary)
                    if !LoginConfiguration.appleEnabled || LoginConfiguration.googleClientID == nil {
                        Text("Account setup is still being completed for this development build. You can keep logging on this device.")
                            .font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("loginSetupMessage")
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
                        Text(message).font(.subheadline).foregroundStyle(.red)
                        Button("Dismiss message") { auth.errorMessage = nil }
                    }
                    Text("Your log and route media stay on this iPhone. Sign-in doesn’t turn on cloud sync. Your guest log remains separate; use backup and restore to move it into your account.")
                        .font(.footnote).foregroundStyle(.secondary)
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
