import SwiftUI

/// Tracks people send you over iMessage, and the ones you send back.
///
/// Replaces the old Feed, which read Xomify's own `/shares/*` — the retired
/// group-sharing system. That is why it kept showing songs from groups that no
/// longer exist. This reads Xomtracks, the same source as the web app.
struct SharesView: View {

    @State private var viewModel = SharesViewModel()

    var body: some View {
        ZStack {
            Color.xomifyDark.ignoresSafeArea()

            VStack(spacing: 0) {
                filters

                if viewModel.isLoading {
                    Spacer()
                    XomifyLoaderPulse(size: 52)
                    Spacer()
                } else if viewModel.shares.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    list
                }
            }
        }
        .navigationTitle("Shares")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.dismissError() } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Filters

    @ViewBuilder
    private var filters: some View {
        @Bindable var vm = viewModel

        VStack(spacing: XomSpacing.sm) {
            Picker("Direction", selection: $vm.direction) {
                ForEach(XtDirection.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: XomSpacing.xs) {
                    ForEach(XtTimeWindow.allCases) { option in
                        Button {
                            vm.window = option
                        } label: {
                            Text(option.label)
                                .font(.xomifyCaption)
                                .padding(.horizontal, XomSpacing.sm)
                                .padding(.vertical, 6)
                                .background(
                                    vm.window == option
                                        ? Color.xomifyGreen.opacity(0.25)
                                        : Color.white.opacity(0.06),
                                    in: Capsule()
                                )
                                .foregroundStyle(vm.window == option ? Color.xomifyGreen : .white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, XomSpacing.md)
        .padding(.vertical, XomSpacing.sm)
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: XomSpacing.sm) {
                ForEach(viewModel.shares) { share in
                    ShareRow(share: share) {
                        Task { await viewModel.toggleHeard(share) }
                    }
                }
            }
            .padding(.horizontal, XomSpacing.md)
            .padding(.bottom, XomSpacing.lg)
        }
        .refreshable { await viewModel.load() }
    }

    private var emptyState: some View {
        VStack(spacing: XomSpacing.sm) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.35))
            Text(viewModel.direction == .incoming ? "No shares received" : "No shares sent")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Tracks shared over iMessage show up here. Try a wider time window.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, XomSpacing.xl)
        }
    }
}

// MARK: - Row

private struct ShareRow: View {
    let share: XtShare
    let onToggleHeard: () -> Void

    var body: some View {
        HStack(spacing: XomSpacing.sm) {
            AsyncImage(url: share.albumArt) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.xomifyCard
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: XomRadius.sm))

            VStack(alignment: .leading, spacing: 2) {
                Text(share.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(share.displayArtist)
                    .font(.xomifyCaption)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)

                if let who = share.displaySharer, let when = share.sentAt {
                    Text("\(who) · \(when.formatted(.relative(presentation: .named)))")
                        .font(.xomifyCaption)
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            // Only offered once the backend has matched the track — heard state
            // is keyed on trackKey, which an unmatched share does not have.
            if share.trackKey != nil {
                Button(action: onToggleHeard) {
                    Image(systemName: (share.heard ?? false) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle((share.heard ?? false) ? Color.xomifyGreen : .white.opacity(0.35))
                }
                .buttonStyle(.plain)
                .accessibilityLabel((share.heard ?? false) ? "Mark unheard" : "Mark heard")
            }
        }
        .padding(XomSpacing.sm)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: XomRadius.md))
        .contextMenu {
            if let url = share.spotifyURL {
                Link(destination: url) {
                    Label("Open in Spotify", systemImage: "arrow.up.right.square")
                }
            }
        }
    }
}
