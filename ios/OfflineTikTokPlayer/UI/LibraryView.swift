import SwiftUI
import PlayerCore

private enum LibraryDestination: Hashable {
    case imported(String)
    case history
    case liked
    case personal(String)

    var importedID: String? {
        if case .imported(let id) = self { return id }
        return nil
    }

    var activeSource: PlaybackService.ActiveSource {
        switch self {
        case .imported(let id): return .imported(id)
        case .personal(let id): return .personal(id)
        case .history: return .history
        case .liked: return .liked
        }
    }
}

struct LibraryView: View {
    @Binding var importing: Bool
    @Environment(AppModel.self) private var app
    @State private var selected = Set<String>()
    @State private var isMixing = false
    @State private var query = ""
    @State private var matches: [MediaRecord] = []

    private var importedPlaylists: [PlaylistRecord] {
        let imported = app.library.catalog.playlists.filter { !$0.id.hasPrefix("local:") }
        return app.personal.orderedPlaylists(imported)
    }

    private var localPlaylists: [PlaylistRecord] {
        app.library.catalog.playlists.filter { $0.id.hasPrefix("local:") }
    }

    private var totalVideosCount: Int {
        app.library.catalog.media.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    searchBar
                    if query.isEmpty {
                        playlistsSection
                        activitySection
                        globalActionsSection
                    } else {
                        searchResultsSection
                    }
                    if let status = app.library.refreshStatus {
                        Label(status, systemImage: "arrow.triangle.2.circlepath")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                    if let message = app.library.message {
                        Text(message)
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .background(Color.black)
            .navigationTitle("Library")
            .onChange(of: query) { _, _ in updateMatches() }
            .onChange(of: app.library.catalog.updatedAt) { _, _ in updateMatches() }
            .refreshable { await app.library.refresh(checkTikTok: true) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { app.playback.setAudioOnly(!app.playback.isAudioOnly) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "headphones")
                            Text(app.playback.isAudioOnly ? "Audio On" : "Audio")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(app.playback.isAudioOnly ? Color.cyan : Color.primary)
                    }
                    .accessibilityLabel("Audio only, \(app.playback.isAudioOnly ? "On" : "Off")")
                    .accessibilityIdentifier("library.audioOnly")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button("New playlist", systemImage: "text.badge.plus") { app.sheet = .newPlaylist }
                        Button("Import from Files", systemImage: "folder.badge.plus") { importing = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add playlist or import videos")
                    Button { app.sheet = .settings } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(for: LibraryDestination.self) { PlaylistView(destination: $0) }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                totalVideosCount > 0
                    ? "Search \(totalVideosCount.formatted()) videos or creators"
                    : "Title or creator",
                text: $query
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Playlists")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                if app.library.catalog.playlists.count > 1 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isMixing.toggle()
                            if !isMixing { selected.removeAll() }
                        }
                    } label: {
                        Text(isMixing ? "Done" : "Mix multiple")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.cyan)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)

            if isMixing, !selected.isEmpty {
                HStack(spacing: 10) {
                    Button { playSelected(shuffle: false) } label: {
                        Label("Play \(selected.count)", systemImage: "play.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.cyan, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    Button { playSelected(shuffle: true) } label: {
                        Label("Shuffle \(selected.count)", systemImage: "shuffle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Text("\(selected.count) selected · shared videos play once")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }

            if importedPlaylists.isEmpty && app.personal.playlists.isEmpty && localPlaylists.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Bring your music with you").font(.headline)
                    Text("Connect your private library in Settings, or add videos from Files to try the player.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Add local videos") { importing = true }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ForEach(importedPlaylists) { playlist in
                    playlistCard(
                        playlist: playlist,
                        destination: .imported(playlist.id),
                        pinID: playlist.id,
                        isPersonal: false
                    )
                }
                ForEach(app.personal.playlists) { playlist in
                    playlistCard(
                        playlist: playlist,
                        destination: .personal(playlist.id),
                        pinID: nil,
                        isPersonal: true
                    )
                }
                if !localPlaylists.isEmpty {
                    Text("Imported from Files")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                        .padding(.horizontal, 2)
                    ForEach(localPlaylists) { playlist in
                        playlistCard(
                            playlist: playlist,
                            destination: .imported(playlist.id),
                            pinID: playlist.id,
                            isPersonal: false
                        )
                    }
                }
            }
        }
    }

    private func playlistCard(playlist: PlaylistRecord, destination: LibraryDestination,
                              pinID: String?, isPersonal: Bool) -> some View {
        let isPinned = pinID.map { app.personal.isPinned($0) } ?? false
        let isActive = app.playback.current != nil && app.playback.activeSource == destination.activeSource
        let isLastPlayed = !isActive && !isPinned && pinID != nil && app.personal.lastPlayedPlaylistID == pinID
        let coverItem = coverMedia(for: playlist)
        let isSelected = selected.contains(playlist.id)

        return HStack(spacing: 12) {
            if isMixing && !isPersonal {
                Button {
                    if isSelected { selected.remove(playlist.id) } else { selected.insert(playlist.id) }
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? Color.cyan : Color.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Select \(playlist.name)")
            }

            NavigationLink(value: destination) {
                HStack(spacing: 12) {
                    if !(isMixing && !isPersonal) {
                        PlaylistArtwork(item: coverItem, isPersonal: isPersonal, accentIndex: abs(playlist.id.hashValue))
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(playlist.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 4) {
                            if isActive {
                                HStack(spacing: 3) {
                                    Image(systemName: "waveform")
                                    Text("Playing")
                                }
                                .foregroundStyle(.cyan)
                                .fontWeight(.semibold)
                                Text("·").foregroundStyle(.secondary)
                            } else if isPinned {
                                HStack(spacing: 3) {
                                    Image(systemName: "pin.fill")
                                    Text("Pinned")
                                }
                                .foregroundStyle(.cyan)
                                .fontWeight(.semibold)
                                Text("·").foregroundStyle(.secondary)
                            } else if isLastPlayed {
                                Text("Recent")
                                    .foregroundStyle(.cyan)
                                    .fontWeight(.semibold)
                                Text("·").foregroundStyle(.secondary)
                            }
                            Text("\(playlist.itemIDs.count.formatted()) videos")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .contain)

            if !(isMixing && !isPersonal) {
                HStack(spacing: 8) {
                    Button {
                        quickPlay(playlist: playlist, destination: destination, shuffle: true)
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.11), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Shuffle \(playlist.name)")

                    Button {
                        quickPlay(playlist: playlist, destination: destination, shuffle: false)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 36, height: 36)
                            .background(Color.cyan, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play \(playlist.name)")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isPinned || isActive ? Color.cyan.opacity(0.11) : Color(white: 0.095))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isPinned || isActive ? Color.cyan.opacity(0.32) : Color.white.opacity(0.07), lineWidth: 1)
        )
        .contextMenu {
            Button("Play", systemImage: "play.fill") {
                quickPlay(playlist: playlist, destination: destination, shuffle: false)
            }
            Button("Shuffle", systemImage: "shuffle") {
                quickPlay(playlist: playlist, destination: destination, shuffle: true)
            }
            if let pinID {
                Button(isPinned ? "Unpin" : "Pin to top", systemImage: isPinned ? "pin.slash" : "pin") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        app.personal.togglePin(pinID)
                    }
                }
            }
            if !isPersonal {
                Button("Save playlist offline", systemImage: "arrow.down.circle") {
                    app.downloads.enqueue(playlist.itemIDs.compactMap { app.library.catalog.mediaByID[$0] })
                    if let message = app.downloads.message { app.alert = message }
                }
            }
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Activity")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Button { app.sheet = .newPlaylist } label: {
                    Label("New playlist", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.cyan)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New playlist")
            }
            .padding(.horizontal, 2)

            HStack(spacing: 10) {
                activityTile(.history, title: "History", icon: "clock.arrow.circlepath",
                             tint: .cyan, count: app.personal.history.count)
                activityTile(.liked, title: "Liked", icon: "heart.fill",
                             tint: .pink, count: app.personal.liked.count)
            }
        }
    }

    private func activityTile(_ destination: LibraryDestination, title: String, icon: String,
                              tint: Color, count: Int) -> some View {
        NavigationLink(value: destination) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("\(count.formatted()) videos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.095), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
    }

    private var globalActionsSection: some View {
        HStack(spacing: 10) {
            Button { playSelected(shuffle: false) } label: {
                Label(
                    selected.isEmpty
                        ? (totalVideosCount > 0 ? "Play all (\(totalVideosCount.formatted()))" : "Play all")
                        : "Play selected",
                    systemImage: "play.fill"
                )
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.cyan, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            Button { playSelected(shuffle: true) } label: {
                Label(selected.isEmpty ? "Shuffle all" : "Shuffle", systemImage: "shuffle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(matches.count.formatted()) results")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            if matches.isEmpty {
                Text("No matching videos.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
            } else {
                ForEach(matches) { item in
                    MediaRow(item: item, playlistIDs: [])
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(white: 0.095), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    private func coverMedia(for playlist: PlaylistRecord) -> MediaRecord? {
        for id in playlist.itemIDs.prefix(12) {
            if let item = app.library.catalog.mediaByID[id], item.artwork != nil {
                return item
            }
        }
        return playlist.itemIDs.first.flatMap { app.library.catalog.mediaByID[$0] }
    }

    private func updateMatches() { matches = app.library.catalog.search(query) }

    private func quickPlay(playlist: PlaylistRecord, destination: LibraryDestination, shuffle: Bool) {
        if let importedID = destination.importedID {
            app.personal.recordPlayedPlaylist(importedID)
            app.playback.start(playlistIDs: [importedID], shuffle: shuffle, source: .imported(importedID))
        } else {
            app.playback.start(playlistIDs: [], shuffle: shuffle, within: playlist.itemIDs, source: destination.activeSource)
        }
        if app.playback.current != nil, !app.playback.isAudioOnly { app.tab = .player }
    }

    private func playSelected(shuffle: Bool) {
        let ids = app.library.catalog.playlists.filter { selected.contains($0.id) }.map(\.id)
        if ids.count == 1 {
            app.personal.recordPlayedPlaylist(ids[0])
        }
        app.playback.start(playlistIDs: ids, shuffle: shuffle)
        if app.playback.current != nil, !app.playback.isAudioOnly { app.tab = .player }
    }
}

private struct PlaylistArtwork: View {
    let item: MediaRecord?
    let isPersonal: Bool
    let accentIndex: Int
    @Environment(AppModel.self) private var app
    @State private var image: UIImage?

    private var gradient: LinearGradient {
        let palettes: [(Color, Color)] = [
            (Color.cyan, Color.indigo),
            (Color.orange, Color.pink),
            (Color.mint, Color.teal),
            (Color.purple, Color.blue)
        ]
        let pair = isPersonal ? (Color.teal, Color.cyan) : palettes[accentIndex % palettes.count]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        ZStack {
            gradient
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: isPersonal ? "bookmark.fill" : "music.note.list")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .clipped()
        .task(id: item?.artwork?.sha256) {
            guard let item else { image = nil; return }
            let loaded = await app.artwork.image(for: item)
            if !Task.isCancelled { image = loaded }
        }
        .accessibilityHidden(true)
    }
}

private struct PlaylistView: View {
    let destination: LibraryDestination
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var matches: [MediaRecord] = []

    private var playlist: PlaylistRecord? {
        switch destination {
        case .imported(let id): return app.library.catalog.playlists.first { $0.id == id }
        case .personal(let id): return app.personal.playlists.first { $0.id == id }
        case .history: return PlaylistRecord(id: "history", name: "History", itemIDs: app.personal.history)
        case .liked: return PlaylistRecord(id: "liked", name: "Liked", itemIDs: app.personal.liked)
        }
    }

    var body: some View {
        if let playlist { detail(playlist) }
        else { ContentUnavailableView("Playlist unavailable", systemImage: "rectangle.stack") }
    }

    private func detail(_ playlist: PlaylistRecord) -> some View {
        let catalogIDs = destination.importedID.map { [$0] } ?? []
        let personalIDs = destination.importedID == nil ? playlist.itemIDs : nil
        let available = app.library.catalog.queue(playlistIDs: catalogIDs, localIDs: app.downloads.readyIDs,
            offlineOnly: !app.network.isConnected, within: personalIDs).count
        return List {
            Section {
                HStack(spacing: 10) {
                    Button { play(catalogIDs, within: personalIDs, shuffle: false) } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.cyan, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    Button { play(catalogIDs, within: personalIDs, shuffle: true) } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }.disabled(available == 0).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                if let importedID = destination.importedID {
                    let isPinned = app.personal.isPinned(importedID)
                    Button {
                        app.personal.togglePin(importedID)
                    } label: {
                        Label(isPinned ? "Pinned to top of Library" : "Pin to top of Library",
                              systemImage: isPinned ? "pin.fill" : "pin")
                    }
                    Button {
                        app.downloads.enqueue(playlist.itemIDs.compactMap { app.library.catalog.mediaByID[$0] })
                        if let message = app.downloads.message { app.alert = message }
                    } label: {
                        Label("Save playlist offline · \(estimate(playlist))", systemImage: "arrow.down.circle")
                    }
                }
                Text("\(playlist.itemIDs.count.formatted()) entries · \(available.formatted()) available")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if matches.isEmpty {
                Text(query.isEmpty ? emptyMessage : "No matching videos.").foregroundStyle(.secondary)
            }
            ForEach(matches) { item in
                MediaRow(item: item, playlistIDs: catalogIDs, itemIDs: personalIDs, source: destination.activeSource)
            }
        }
        .navigationTitle(playlist.name).navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search this playlist")
        .onAppear { updateMatches(playlist) }
        .onChange(of: query) { _, _ in updateMatches(playlist) }
        .onChange(of: playlist.itemIDs) { _, _ in updateMatches(playlist) }
        .onChange(of: app.library.catalog.updatedAt) { _, _ in updateMatches(playlist) }
    }

    private var emptyMessage: String {
        switch destination {
        case .history: return "Videos you watch will appear here."
        case .liked: return "Tap the heart on a video to save it here."
        case .personal: return "Tap the bookmark on a video to add it to this playlist."
        case .imported: return "No videos in this playlist yet."
        }
    }

    private func estimate(_ playlist: PlaylistRecord) -> String {
        let assets = playlist.itemIDs.compactMap { app.library.catalog.mediaByID[$0]?.asset }
        let bytes = DownloadRecord.estimatedBytes(assets, verifiedHashes: Set(app.downloads.records.values.filter(\.isReady).map(\.asset.sha256)))
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    private func updateMatches(_ playlist: PlaylistRecord) { matches = app.library.catalog.search(query, within: playlist.itemIDs) }
    private func play(_ catalogIDs: [String], within personalIDs: [String]?, shuffle: Bool) {
        if let importedID = destination.importedID {
            app.personal.recordPlayedPlaylist(importedID)
        }
        app.playback.start(playlistIDs: catalogIDs, shuffle: shuffle, within: personalIDs, source: destination.activeSource)
        if app.playback.current != nil, !app.playback.isAudioOnly { app.tab = .player }
    }
}

struct MediaRow: View {
    let item: MediaRecord
    let playlistIDs: [String]
    var itemIDs: [String]? = nil
    var source: PlaybackService.ActiveSource? = nil
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    private var saved: Bool { app.downloads.records[item.id]?.isReady == true }
    private var playable: Bool { saved || (item.status == .ready && item.asset != nil) }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                guard playable else { app.alert = "This post does not have an archived video yet. Its place in your playlist is preserved."; return }
                if itemIDs != nil, !saved, !app.network.isConnected { app.alert = "Connect to the internet to play this video."; return }
                if playlistIDs.count == 1 { app.personal.recordPlayedPlaylist(playlistIDs[0]) }
                app.playback.start(playlistIDs: playlistIDs, at: item.id, shuffle: app.playback.queue.isShuffled,
                                   within: itemIDs, source: source)
                if !app.playback.isAudioOnly { app.tab = .player }
            } label: {
                HStack(spacing: 12) {
                    MediaThumbnail(item: item).frame(width: 55, height: 72).clipShape(.rect(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title).font(.subheadline.weight(.medium)).lineLimit(2).foregroundStyle(playable ? .primary : .secondary)
                        Text(item.creator).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if !playable { Text(item.status == .unavailable ? "Unavailable" : "Not archived yet").font(.caption2).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.buttonStyle(.plain)
            if saved { Image(systemName: "checkmark.circle.fill").foregroundStyle(.cyan).accessibilityLabel("Saved offline") }
            else if let transfer = app.downloads.records[item.id], [.queued, .resolving, .downloading, .verifying].contains(transfer.state) {
                ProgressView(value: transfer.progress).frame(width: 30).accessibilityLabel("Downloading \(Int(transfer.progress * 100)) percent")
            }
        }
        .contextMenu {
            if let url = item.tiktokPostURL {
                Button("Open in TikTok", systemImage: "arrow.up.right.square") { openURL(url) }
            }
            if saved { Button("Remove offline copy", systemImage: "trash", role: .destructive) { app.downloads.remove(item.id) } }
            else if item.asset != nil { Button("Save offline", systemImage: "arrow.down.circle") { app.downloads.enqueue([item]); if let message = app.downloads.message { app.alert = message } } }
        }
    }
}
