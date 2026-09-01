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
                    XomifyLoaderPaint(size: 64)
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
        // One header for every destination. Half of them were falling back to
        // the plain nav bar, which renders grey on this background.
        .safeAreaInset(edge: .top) {
            BrandGradientHeader(
                "Shares",
                subtitle: viewModel.direction == .incoming ? "SENT TO YOU OVER IMESSAGE" : "TRACKS YOU SENT",
                systemImage: "square.and.arrow.up"
            )
        }
        .toolbar(.hidden, for: .navigationBar)
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

    private var heard: Bool { share.heard ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: XomSpacing.sm) {
            HStack(spacing: XomSpacing.sm) {
                AsyncImage(url: share.albumArt) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.xomifyCard
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: XomRadius.sm))

                VStack(alignment: .leading, spacing: 3) {
                    Text(share.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(share.displayArtist)
                        .font(.xomifyCaption)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)

                    if let album = share.albumName, !album.isEmpty {
                        Text(album)
                            .font(.xomifyCaption)
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if let rating = share.rating, (rating.count ?? 0) > 0 {
                    ratingBadge(rating)
                }
            }

            // Who and when, spelled out. "Dom · 3 days ago" is the whole point
            // of the screen and was previously the least prominent line on it.
            if let who = share.displaySharer {
                HStack(spacing: 4) {
                    Image(systemName: share.direction == .incoming ? "arrow.down.left" : "arrow.up.right")
                        .font(.caption2.weight(.bold))
                    Text(share.direction == .incoming ? "From \(who)" : "To \(who)")
                        .fontWeight(.medium)
                    if let when = share.sentAt {
                        Text("· \(when.formatted(.relative(presentation: .named)))")
                    }
                }
                .font(.xomifyCaption)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
            }

            if let genres = share.genres, !genres.isEmpty {
                HStack(spacing: XomSpacing.xs) {
                    ForEach(genres.prefix(3), id: \.self) { genre in
                        Text(genre)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.xomifyPurple.opacity(0.25), in: Capsule())
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }

            footer
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

    private func ratingBadge(_ rating: XtRating) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 2) {
                Image(systemName: "star.fill").font(.system(size: 9))
                Text(String(format: "%.1f", rating.avg ?? 0))
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(Color.xomifyGreen)
            Text("\(rating.count ?? 0) rated")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: XomSpacing.sm) {
            // A bare circle told nobody what it did. The label is the fix --
            // this is the one control on the row and it was unexplained.
            if share.trackKey != nil {
                Button(action: onToggleHeard) {
                    HStack(spacing: 5) {
                        Image(systemName: heard ? "checkmark.circle.fill" : "circle")
                            .font(.caption)
                        Text(heard ? "Listened" : "Mark listened")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(heard ? Color.xomifyGreen : .white.opacity(0.6))
                    .padding(.horizontal, XomSpacing.sm)
                    .padding(.vertical, 5)
                    .background(
                        heard ? Color.xomifyGreen.opacity(0.15) : Color.white.opacity(0.06),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            } else {
                // Unmatched shares have no trackKey, so there is nothing to
                // mark. Saying why beats showing a control that does nothing.
                Label("Not matched to Spotify yet", systemImage: "questionmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer(minLength: 0)

            if let url = share.spotifyURL {
                Link(destination: url) {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.spotifyGreen)
                }
            }
        }
    }
}
