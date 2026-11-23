import XCTest
@testable import PlayerCore

final class PersonalLibraryTests: XCTestCase {
    @MainActor
    func testRecentVideosAreUniqueAndRestoreInLastPlayedOrder() async throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let library = PersonalLibrary(defaults: defaults)
        library.recordPlayed("a")
        library.recordPlayed("b")
        library.recordPlayed("a")
        library.recordPlayed("a")
        XCTAssertEqual(PersonalLibrary(defaults: defaults).history, ["a", "b"])
    }

    @MainActor
    func testLikesAndBookmarksAreIndependentAndPersistWithoutDuplicateMembership() async throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let library = PersonalLibrary(defaults: defaults)
        let playlist = try library.createPlaylist(named: "  Fav 1\n", adding: "a")
        library.toggleLike("a")
        library.toggleLike("b")
        library.toggleLike("a")
        try library.toggleMembership("b", in: playlist.id)
        let reopened = PersonalLibrary(defaults: defaults)
        XCTAssertEqual(reopened.liked, ["b"])
        XCTAssertEqual(reopened.playlists, [PlaylistRecord(id: playlist.id, name: "Fav 1", itemIDs: ["a", "b"])])
        try reopened.toggleMembership("a", in: playlist.id)
        XCTAssertEqual(PersonalLibrary(defaults: defaults).playlists.first?.itemIDs, ["b"])
        XCTAssertEqual(reopened.liked, ["b"])
    }

    @MainActor
    func testEmptyAndDuplicateNamesDoNotCreatePlaylists() async throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let library = PersonalLibrary(defaults: defaults)
        let empty = try library.createPlaylist(named: "Useful Advice")
        XCTAssertThrowsError(try library.createPlaylist(named: " useful advice ", adding: "a"))
        XCTAssertThrowsError(try library.createPlaylist(named: " \n"))
        XCTAssertEqual(library.playlists, [empty])
        XCTAssertTrue(empty.itemIDs.isEmpty)
    }

    func testPersonalQueueResolvesAgainstCurrentCatalogWithoutMixingImportedMembership() throws {
        let catalog = try LibraryCatalog.decode(Data(CatalogTests.fixture.utf8))
        let personal = ["2", "gone", "2", "3", "1"]
        XCTAssertEqual(catalog.queue(playlistIDs: [], within: personal), ["2", "1"])
        XCTAssertEqual(catalog.queue(playlistIDs: [], localIDs: ["3", "1"], offlineOnly: true, within: personal), ["3", "1"])
        XCTAssertTrue(catalog.queue(playlistIDs: [], within: []).isEmpty)
        XCTAssertEqual(catalog.queue(playlistIDs: ["music"]), ["1", "2"])
    }

    @MainActor
    func testPinnedAndLastPlayedPlaylistsPersistAndOrderFirst() throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let library = PersonalLibrary(defaults: defaults)
        let first = PlaylistRecord(id: "p1", name: "First", itemIDs: ["1"])
        let second = PlaylistRecord(id: "p2", name: "Second", itemIDs: ["2"])
        let third = PlaylistRecord(id: "p3", name: "Third", itemIDs: ["3"])
        let all = [first, second, third]

        XCTAssertEqual(library.orderedPlaylists(all).map(\.id), ["p1", "p2", "p3"])

        library.recordPlayedPlaylist("p3")
        XCTAssertEqual(library.orderedPlaylists(all).map(\.id), ["p3", "p1", "p2"])

        library.togglePin("p2")
        XCTAssertTrue(library.isPinned("p2"))
        XCTAssertEqual(library.orderedPlaylists(all).map(\.id), ["p2", "p3", "p1"])

        // Persists across reload and ignores unknown/deleted pinned IDs cleanly.
        let reloaded = PersonalLibrary(defaults: defaults)
        XCTAssertTrue(reloaded.isPinned("p2"))
        XCTAssertEqual(reloaded.lastPlayedPlaylistID, "p3")
        XCTAssertEqual(reloaded.orderedPlaylists(all).map(\.id), ["p2", "p3", "p1"])
        XCTAssertEqual(reloaded.orderedPlaylists([first, third]).map(\.id), ["p3", "p1"])

        reloaded.togglePin("p2")
        XCTAssertFalse(reloaded.isPinned("p2"))
        XCTAssertEqual(PersonalLibrary(defaults: defaults).orderedPlaylists(all).map(\.id), ["p3", "p1", "p2"])
    }

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let name = "personal-library-tests-\(UUID())"
        return (try XCTUnwrap(UserDefaults(suiteName: name)), name)
    }
}
