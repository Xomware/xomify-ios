import SwiftUI

/// Invites screen: generate a shareable code or paste one you've received.
struct InvitesView: View {

    @State private var viewModel = InvitesViewModel()
    @State private var isLoadingUser = true
    @State private var userEmail: String?

    private let spotifyService = SpotifyService.shared

    var body: some View {
        ZStack {
            Color.xomifyDark.ignoresSafeArea()
            content
        }
        .navigationTitle("Invites")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadUser() }
        .tint(Color.xomifyGreen)
    }

    @ViewBuilder
    private var content: some View {
        if isLoadingUser {
            ProgressView().tint(.xomifyGreen)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    generateSection
                    Divider().background(Color.gray.opacity(0.3))
                    acceptSection
                    if let error = viewModel.errorMessage {
                        Text(error).font(.caption).foregroundColor(.red)
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Generate section

    private var generateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Invite a Friend")
                .font(.headline)
                .foregroundColor(.white)
            Text("Share a link. When they accept, you'll be friends.")
                .font(.caption)
                .foregroundColor(.gray)

            if let code = viewModel.inviteCode {
                VStack(alignment: .leading, spacing: 10) {
                    codeCard(code: code)

                    HStack(spacing: 10) {
                        if let urlString = viewModel.shareUrl, let url = URL(string: urlString) {
                            ShareLink(item: url) {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Share")
                                }
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Color.xomifyGreen)
                                .foregroundColor(.black)
                                .cornerRadius(16)
                            }
                        }

                        Button {
                            copy(code)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.doc")
                                Text("Copy Code")
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.white.opacity(0.1))
                            .foregroundColor(.white)
                            .cornerRadius(16)
                        }

                        if let urlString = viewModel.shareUrl {
                            Button {
                                copy(urlString)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "link")
                                    Text("Copy Link")
                                }
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Color.white.opacity(0.1))
                                .foregroundColor(.white)
                                .cornerRadius(16)
                            }
                        }
                    }

                    if let exp = viewModel.expiresAt {
                        Text("Expires \(exp)")
                            .font(.caption2).foregroundColor(.gray)
                    }
                }
            }

            Button {
                Task {
                    if let email = userEmail { await viewModel.generate(email: email) }
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isGenerating {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "link.badge.plus")
                        Text(viewModel.inviteCode == nil ? "Generate Invite Link" : "Generate New Link")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(LinearGradient.xomifyGradient)
                .foregroundColor(.white)
                .cornerRadius(25)
            }
            .disabled(viewModel.isGenerating || userEmail == nil)
        }
    }

    private func codeCard(code: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CODE").font(.caption2).foregroundColor(.gray)
            Text(code)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .textSelection(.enabled)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.xomifyCard)
        .cornerRadius(12)
    }

    // MARK: - Accept section

    private var acceptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Have a Code?")
                .font(.headline)
                .foregroundColor(.white)
            Text("Paste it below to add the sender as a friend.")
                .font(.caption)
                .foregroundColor(.gray)

            TextField("Paste invite code", text: $viewModel.codeInput)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(10)
                .foregroundColor(.white)

            Button {
                Task {
                    if let email = userEmail { await viewModel.accept(email: email) }
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isAccepting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Accept Invite")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.xomifyPurple)
                .foregroundColor(.white)
                .cornerRadius(25)
            }
            .disabled(viewModel.isAccepting || viewModel.codeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || userEmail == nil)

            if let success = viewModel.acceptSuccessMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.xomifyGreen)
                    Text(success).font(.caption).foregroundColor(.white)
                }
            }
        }
    }

    // MARK: - Helpers

    private func copy(_ value: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = value
        #endif
    }

    private func loadUser() async {
        isLoadingUser = true
        do {
            let user = try await spotifyService.getCurrentUser()
            userEmail = user.email
        } catch {
            viewModel.errorMessage = "Failed to load profile: \(error.localizedDescription)"
        }
        isLoadingUser = false
    }
}

#Preview {
    NavigationStack { InvitesView() }
}
