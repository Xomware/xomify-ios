import XCTest
@testable import Xomify_iOS

@MainActor
final class UserProfileViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeSpotifyUser(
        email: String = "me@example.com",
        displayName: String? = "Me",
        avatarUrl: String? = nil,
        followers: Int? = nil
    ) -> SpotifyUser {
        SpotifyUser(
            id: "sp-id",
            displayName: displayName,
            email: email,
            images: avatarUrl.map { [SpotifyImage(url: $0, height: nil, width: nil)] },
            followers: followers.map { SpotifyUser.Followers(total: $0) },
            country: nil,
            product: nil,
            externalUrls: nil
        )
    }

    private func makeFriendProfile(
        email: String = "friend@example.com",
        displayName: String? = "Friend",
        avatar: String? = nil,
        followers: Int? = nil,
        following: Int? = nil,
        friends: Int? = nil,
        shares: Int? = nil
    ) -> FriendProfile {
        FriendProfile(
            email: email,
            displayName: displayName,
            userId: nil,
            avatar: avatar,
            followersCount: followers,
            followingCount: following,
            playlistCount: nil,
            friendsCount: friends,
            shareCount: shares,
            topSongs: nil,
            topArtists: nil,
            topGenres: nil,
            playlists: nil
        )
    }

    // MARK: - .me header

    func test_loadHeader_me_populatesFromSpotify() async {
        let spotify = MockSpotifyCurrentUserProviding()
        spotify.response = makeSpotifyUser(
            email: "me@example.com",
            displayName: "Dom",
            avatarUrl: "https://img.example.com/me.jpg",
            followers: 42
        )
        let xomify = MockXomifyServiceProtocol()

        let vm = UserProfileViewModel(
            context: .me,
            xomifyService: xomify,
            spotifyService: spotify
        )

        await vm.loadHeader()

        XCTAssertEqual(vm.displayName, "Dom")
        XCTAssertEqual(vm.profileEmail, "me@example.com")
        XCTAssertEqual(vm.callerEmail, "me@example.com")
        XCTAssertEqual(vm.avatarURL?.absoluteString, "https://img.example.com/me.jpg")
        XCTAssertEqual(vm.followersCount, 42)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
        XCTAssertTrue(xomify.getFriendProfileCalls.isEmpty)
    }

    func test_loadHeader_me_fallsBackToYouWhenNameMissing() async {
        let spotify = MockSpotifyCurrentUserProviding()
        spotify.response = makeSpotifyUser(displayName: nil)

        let vm = UserProfileViewModel(
            context: .me,
            xomifyService: MockXomifyServiceProtocol(),
            spotifyService: spotify
        )

        await vm.loadHeader()

        XCTAssertEqual(vm.displayName, "You")
    }

    // MARK: - .other header

    func test_loadHeader_other_populatesFromFriendProfile() async {
        let spotify = MockSpotifyCurrentUserProviding()
        spotify.response = makeSpotifyUser(email: "me@example.com")
        let xomify = MockXomifyServiceProtocol()
        xomify.getFriendProfileResponse = makeFriendProfile(
            email: "friend@example.com",
            displayName: "Friend Name",
            avatar: "https://img.example.com/friend.jpg",
            followers: 10,
            following: 5,
            friends: 7,
            shares: 3
        )

        let vm = UserProfileViewModel(
            context: .other(email: "friend@example.com"),
            xomifyService: xomify,
            spotifyService: spotify
        )

        await vm.loadHeader()

        XCTAssertEqual(vm.displayName, "Friend Name")
        XCTAssertEqual(vm.profileEmail, "friend@example.com")
        XCTAssertEqual(vm.avatarURL?.absoluteString, "https://img.example.com/friend.jpg")
        XCTAssertEqual(vm.followersCount, 10)
        XCTAssertEqual(vm.followingCount, 5)
        XCTAssertEqual(vm.friendCount, 7)
        XCTAssertEqual(vm.shareCount, 3)
        XCTAssertNotNil(vm.friendProfile)
        XCTAssertEqual(xomify.getFriendProfileCalls.count, 1)
        XCTAssertEqual(xomify.getFriendProfileCalls.first?.email, "me@example.com")
        XCTAssertEqual(xomify.getFriendProfileCalls.first?.profileEmail, "friend@example.com")
    }

    func test_loadHeader_other_fallsBackToEmailWhenNameMissing() async {
        let spotify = MockSpotifyCurrentUserProviding()
        spotify.response = makeSpotifyUser(email: "me@example.com")
        let xomify = MockXomifyServiceProtocol()
        xomify.getFriendProfileResponse = makeFriendProfile(displayName: nil)

        let vm = UserProfileViewModel(
            context: .other(email: "friend@example.com"),
            xomifyService: xomify,
            spotifyService: spotify
        )

        await vm.loadHeader()

        XCTAssertEqual(vm.displayName, "friend@example.com")
    }

    // MARK: - Error surfacing

    func test_loadHeader_me_errorSurfaces() async {
        let spotify = MockSpotifyCurrentUserProviding()
        spotify.error = NSError(
            domain: "spotify", code: 401,
            userInfo: [NSLocalizedDescriptionKey: "Spotify session expired"]
        )

        let vm = UserProfileViewModel(
            context: .me,
            xomifyService: MockXomifyServiceProtocol(),
            spotifyService: spotify
        )

        await vm.loadHeader()

        XCTAssertEqual(vm.errorMessage, "Spotify session expired")
        XCTAssertTrue(vm.displayName.isEmpty)
        XCTAssertFalse(vm.isLoading)
    }

    func test_loadHeader_other_errorFromFriendProfileSurfaces() async {
        let spotify = MockSpotifyCurrentUserProviding()
        spotify.response = makeSpotifyUser(email: "me@example.com")
        let xomify = MockXomifyServiceProtocol()
        xomify.getFriendProfileError = NSError(
            domain: "xomify", code: 500,
            userInfo: [NSLocalizedDescriptionKey: "Profile unavailable"]
        )

        let vm = UserProfileViewModel(
            context: .other(email: "friend@example.com"),
            xomifyService: xomify,
            spotifyService: spotify
        )

        await vm.loadHeader()

        XCTAssertEqual(vm.errorMessage, "Profile unavailable")
        XCTAssertFalse(vm.isLoading)
    }

    func test_loadHeader_missingEmail_throwsProfileError() async {
        let spotify = MockSpotifyCurrentUserProviding()
        spotify.response = makeSpotifyUser(email: "")

        let vm = UserProfileViewModel(
            context: .me,
            xomifyService: MockXomifyServiceProtocol(),
            spotifyService: spotify
        )

        await vm.loadHeader()

        XCTAssertEqual(vm.errorMessage, "Could not resolve signed-in user email.")
    }

    // MARK: - Lazy shares VM

    func test_sharesViewModel_me_targetsCallerEmail() async {
        let spotify = MockSpotifyCurrentUserProviding()
        spotify.response = makeSpotifyUser(email: "me@example.com")

        let vm = UserProfileViewModel(
            context: .me,
            xomifyService: MockXomifyServiceProtocol(),
            spotifyService: spotify
        )

        await vm.loadHeader()

        let shares = vm.sharesViewModel()
        XCTAssertNotNil(shares)
        XCTAssertEqual(shares?.callerEmail, "me@example.com")
        XCTAssertEqual(shares?.targetEmail, "me@example.com")
    }

    func test_sharesViewModel_other_targetsOtherEmail() async {
        let spotify = MockSpotifyCurrentUserProviding()
        spotify.response = makeSpotifyUser(email: "me@example.com")
        let xomify = MockXomifyServiceProtocol()
        xomify.getFriendProfileResponse = makeFriendProfile()

        let vm = UserProfileViewModel(
            context: .other(email: "friend@example.com"),
            xomifyService: xomify,
            spotifyService: spotify
        )

        await vm.loadHeader()

        let shares = vm.sharesViewModel()
        XCTAssertEqual(shares?.callerEmail, "me@example.com")
        XCTAssertEqual(shares?.targetEmail, "friend@example.com")
    }

    func test_sharesViewModel_beforeLoad_returnsNil() {
        let vm = UserProfileViewModel(
            context: .me,
            xomifyService: MockXomifyServiceProtocol(),
            spotifyService: MockSpotifyCurrentUserProviding()
        )

        XCTAssertNil(vm.sharesViewModel())
    }

    func test_sharesViewModel_isCachedAcrossCalls() async {
        let spotify = MockSpotifyCurrentUserProviding()
        spotify.response = makeSpotifyUser(email: "me@example.com")

        let vm = UserProfileViewModel(
            context: .me,
            xomifyService: MockXomifyServiceProtocol(),
            spotifyService: spotify
        )

        await vm.loadHeader()

        let first = vm.sharesViewModel()
        let second = vm.sharesViewModel()
        XCTAssertNotNil(first)
        XCTAssertTrue(first === second, "sharesViewModel should return the same instance on repeated calls")
    }
}
