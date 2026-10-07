import Foundation
import ClerkKit

/// All Clerk SDK calls live here, so if the Clerk iOS API changes you only touch this file.
/// Uses the same Clerk instance (publishable key) as the Android app and the web dashboard.
enum AppConfig {
    static let clerkPublishableKey = "pk_live_Y2xlcmsud29kd2lyZS5jb20k"
}

@MainActor
enum AuthBridge {
    static func configure() {
        Clerk.configure(publishableKey: AppConfig.clerkPublishableKey)
    }

    /// The signed-in user mapped to the app's own model (nil when signed out).
    static var currentUser: PhoneViewModel.UserInfo? {
        guard let u = Clerk.shared.user else { return nil }
        let name = [u.firstName, u.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        let email = u.primaryEmailAddress?.emailAddress ?? ""
        return PhoneViewModel.UserInfo(userId: u.id, name: name.isEmpty ? (u.username ?? "") : name, email: email)
    }

    /// Fresh session JWT for the API `Authorization: Bearer` header.
    static func token() async -> String? {
        do { return try await Clerk.shared.auth.getToken() } catch { return nil }
    }

    /// Google sign-in (same as the Android "Sign in with Google" button).
    static func signInWithGoogle() async throws {
        _ = try await Clerk.shared.auth.signInWithOAuth(provider: .google)
    }

    static func signOut() async {
        try? await Clerk.shared.auth.signOut()
    }

    static func handle(url: URL) async {
        _ = try? await Clerk.shared.handle(url)
    }
}
