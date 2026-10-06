import AppKit
import ImageIO
import QuickLook
import SwiftUI

struct SavedWallpapersView: View {
    var width: CGFloat = 900
    var height: CGFloat = 600
    var displayAspectRatio: CGFloat = 16.0 / 9.0
    var displayName: String?
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedGroupID: String?
    @State private var quickLookURL: URL?
    @FocusState private var galleryFocused: Bool

    private var groups: [PictureHistoryGalleryGroup] {
        PictureHistoryGalleryGroup.make(originals: model.pictureHistoryEntries,
                                        variations: model.savedWallpaperGroups.flatMap(\.wallpapers))
            .filter { $0.original != nil }
    }
    private var selectedGroup: PictureHistoryGalleryGroup? { groups.first { $0.id == selectedGroupID } }
    private var canChoose: Bool {
        selectedGroup?.original.map { FileManager.default.fileExists(atPath: $0.originalURL.path) } ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Previous pictures").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(.bar)
            if groups.isEmpty {
                ContentUnavailableView("Your pictures will appear here", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    if geometry.size.width >= 700 {
                        HStack(spacing: 0) {
                            gallery.frame(width: geometry.size.width * 0.4)
                            Divider()
                            selectionDetail.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        gallery
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if !groups.isEmpty {
                    Text(AppCopy.historyChoiceNotice)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                    Spacer()
                    if !groups.isEmpty {
                        Button("Choose Picture & Idea") { chooseOriginal() }
                            .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                            .disabled(!canChoose)
                            .help("Restores this picture and its idea. \(AppCopy.historyChoiceNotice) \(AppCopy.usePictureAndIdeaAsWallpaper) starts desktop updates.")
                    }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(.bar)
        }
        .frame(width: max(360, width), height: height)
        .quickLookPreview($quickLookURL)
        .onAppear {
            selectedGroupID = groups.first?.id
            galleryFocused = !groups.isEmpty
        }
        .onChange(of: groups.map(\.id)) { _, ids in
            if let selectedGroupID, ids.contains(selectedGroupID) { return }
            selectedGroupID = ids.first
        }
    }

    private var gallery: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(groups) { group in
                        Button {
                            selectedGroupID = group.id
                            galleryFocused = true
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                if let original = group.original {
                                    SavedWallpaperThumbnail(url: original.originalURL, revision: original.importedAt)
                                        .aspectRatio(3.0 / 2, contentMode: .fit)
                                        .clipShape(.rect(cornerRadius: 8))
                                }
                                Text(group.name).font(.headline).lineLimit(1)
                                Text(idea(for: group)).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                            }
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(selectedGroupID == group.id ? Color.accentColor.opacity(0.08) : .clear,
                                        in: .rect(cornerRadius: 12))
                            .overlay { RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(selectedGroupID == group.id ? Color.accentColor : .clear, lineWidth: 2) }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(group.name), \(idea(for: group))")
                        .accessibilityAddTraits(selectedGroupID == group.id ? .isSelected : [])
                        .contextMenu {
                            if let original = group.original {
                                Button("Quick Look") { quickLookURL = original.originalURL }
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([original.originalURL]) }
                            }
                        }
                        .id(group.id)
                    }
                }
                .padding(16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .focusable().focused($galleryFocused)
            .focusEffectDisabled(!NSApp.isFullKeyboardAccessEnabled)
            .accessibilityLabel("Previous original pictures and their ideas")
            .onKeyPress(.upArrow) { navigate(-1); return .handled }
            .onKeyPress(.downArrow) { navigate(1); return .handled }
            .onKeyPress(.space) {
                guard let original = selectedGroup?.original else { return .ignored }
                quickLookURL = original.originalURL; return .handled
            }
            .onKeyPress(.return) {
                guard canChoose else { return .ignored }
                chooseOriginal(); return .handled
            }
            .onChange(of: selectedGroupID) { _, id in
                if let id { scroll.scrollTo(id, anchor: .center) }
            }
        }
    }

    private var selectionDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let group = selectedGroup, let original = group.original {
                Text(group.name).font(.headline)
                SavedWallpaperThumbnail(url: original.originalURL, contentMode: .fit,
                                        maximumPixelSize: 1_600, revision: original.importedAt)
                    .id(original.originalURL).frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("Your idea").font(.headline)
                ScrollView {
                    Text(idea(for: group)).font(.body).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 100)
            }
        }
        .padding(20)
    }

    private func idea(for group: PictureHistoryGalleryGroup) -> String {
        guard let prompt = group.latestVariation?.prompt else { return "Idea not saved" }
        return PromptRenderer.editableText(prompt)
    }

    private func chooseOriginal() {
        guard canChoose, let original = selectedGroup?.original else { return }
        let variation = selectedGroup?.latestVariation
        dismiss()
        Task { @MainActor in model.chooseHistoryPicture(digest: original.digest, variation: variation) }
    }

    private func navigate(_ direction: Int) {
        guard !groups.isEmpty else { return }
        let index = groups.firstIndex { $0.id == selectedGroupID } ?? 0
        selectedGroupID = groups[min(groups.count - 1, max(0, index + direction))].id
    }
}
private struct SavedWallpaperThumbnail: View {
    let url: URL
    var displayAspectRatio: CGFloat?
    var contentMode: ContentMode = .fill
    var maximumPixelSize = 480
    var revision: Date? = nil
    var onDecoded: (@MainActor (URL, Bool) -> Void)? = nil
    var onAspectRatioChange: (@MainActor (URL, Double) -> Void)? = nil
    @State private var image: CGImage?
    @State private var finished = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image {
                    if let displayAspectRatio {
                        ScreenFramedArtwork(image: image, displayAspectRatio: displayAspectRatio)
                    } else {
                        Image(decorative: image, scale: 1).resizable()
                            .aspectRatio(contentMode: contentMode)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                } else if finished {
                    ContentUnavailableView("Picture Unavailable", systemImage: "photo")
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
        .task(id: SavedWallpaperThumbnailCache.Key(url: url, maximumPixelSize: maximumPixelSize, revision: revision)) {
            finished = false
            image = nil
            let result = await SavedWallpaperThumbnailCache.shared.image(at: url, maximumPixelSize: maximumPixelSize, revision: revision)
            guard !Task.isCancelled else { return }
            image = result
            finished = true
            if let result { onAspectRatioChange?(url, Double(result.width) / Double(result.height)) }
            onDecoded?(url, result != nil)
        }
    }
}

private actor SavedWallpaperThumbnailCache {
    struct Key: Hashable { let url: URL; let maximumPixelSize: Int; let revision: Date? }
    static let shared = SavedWallpaperThumbnailCache()
    private var images: [Key: CGImage] = [:]
    private var order: [Key] = []
    private var inFlight: [Key: Task<CGImage?, Never>] = [:]

    func image(at url: URL, maximumPixelSize: Int, revision: Date?) async -> CGImage? {
        let key = Key(url: url, maximumPixelSize: maximumPixelSize, revision: revision)
        if let image = images[key] { return image }
        if let task = inFlight[key] { return await task.value }
        let task = Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil as CGImage? }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            ] as CFDictionary)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result {
            images[key] = result
            order.append(key)
            while order.count > 40 { images.removeValue(forKey: order.removeFirst()) }
        }
        return result
    }
}
