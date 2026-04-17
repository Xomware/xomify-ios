import Foundation

/// ViewModel for Invites: generate a friend invite code / accept one.
@Observable
@MainActor
final class InvitesViewModel {

    var userEmail: String = ""

    // Generated invite
    var inviteCode: String?
    var shareUrl: String?
    var expiresAt: String?
    var isGenerating = false

    // Accept invite
    var codeInput: String = ""
    var isAccepting = false
    var acceptSuccessMessage: String?

    var errorMessage: String?

    private let xomify = XomifyService.shared

    // MARK: - Generate

    func generate(email: String) async {
        guard !email.isEmpty else {
            errorMessage = "Please log in first"
            return
        }
        userEmail = email
        guard !isGenerating else { return }
        isGenerating = true
        errorMessage = nil

        do {
            let response = try await xomify.createInvite(email: email)
            inviteCode = response.inviteCode
            shareUrl = response.shareUrl
            expiresAt = response.expiresAt
        } catch {
            errorMessage = "Failed to generate invite: \(error.localizedDescription)"
            print("❌ Invites: generate failed - \(error)")
        }

        isGenerating = false
    }

    // MARK: - Accept

    func accept(email: String) async {
        userEmail = email
        let code = codeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            errorMessage = "Please enter an invite code"
            return
        }
        guard !isAccepting else { return }
        isAccepting = true
        errorMessage = nil
        acceptSuccessMessage = nil

        do {
            let response = try await xomify.acceptInvite(email: email, inviteCode: code)
            if let friend = response.friendEmail {
                acceptSuccessMessage = "You're now friends with \(friend)"
            } else {
                acceptSuccessMessage = "Invite accepted"
            }
            codeInput = ""
        } catch {
            errorMessage = "Failed to accept invite: \(error.localizedDescription)"
            print("❌ Invites: accept failed - \(error)")
        }

        isAccepting = false
    }
}
