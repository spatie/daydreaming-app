import AppKit
import SwiftUI

/// Reuses one native window per destination. Closing a submission keeps its draft in memory.
@MainActor
final class CommunityWindowController: NSWindowController, NSWindowDelegate {
    private static var about: CommunityWindowController?
    private static var submission: CommunityWindowController?
    private static let draft = PromptSubmissionDraft()
    private static let details = AboutDetails()
    private let isSubmission: Bool

    static func showAbout(postcard: Bool = false) {
        if postcard { details.showAddress = true }
        if about == nil { about = CommunityWindowController(isSubmission: false) }
        about?.present()
    }

    static func showSubmission() {
        if submission == nil { submission = CommunityWindowController(isSubmission: true) }
        submission?.present()
    }

    private init(isSubmission: Bool) {
        self.isSubmission = isSubmission
        let width: CGFloat = isSubmission ? 560 : 460
        let height = min(isSubmission ? 550.0 : 680.0, (NSScreen.main?.visibleFrame.height ?? 800) - 60)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = isSubmission ? "Ask for a feature" : "About Daydreaming"
        window.identifier = NSUserInterfaceItemIdentifier(isSubmission ? "daydreaming.submit-prompt" : "daydreaming.about")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isReleasedWhenClosed = false
        window.center()
        if isSubmission {
            window.contentViewController = NSHostingController(rootView: PromptSubmissionView(draft: Self.draft, close: { [weak window] in window?.performClose(nil) }).frame(width: width, height: height))
        } else {
            window.contentViewController = NSHostingController(rootView: DaydreamingAboutView(details: Self.details, close: { [weak window] in window?.performClose(nil) }).frame(width: width, height: height))
        }
        super.init(window: window)
        window.delegate = self
    }
    required init?(coder: NSCoder) { nil }
    private func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        if !AppRuntime.isPreview { NSApp.activate() }
    }
    func windowWillClose(_ notification: Notification) {
        if isSubmission { Self.draft.closed(); Self.submission = nil }
        else { Self.about = nil }
    }
}

struct PromptSubmissionView: View {
    @Bindable var draft: PromptSubmissionDraft
    let close: () -> Void
    @FocusState private var textFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 5) {
                    Text("What should Daydreaming do next?").font(.title2.weight(.semibold))
                    Text("Tell us about a feature you'd love.").foregroundStyle(.secondary)
                }
            }
            if let reference = draft.reference {
                Spacer()
                Image(systemName: "envelope.badge").font(.system(size: 36)).foregroundStyle(.purple)
                Text("Your request is on its way.").font(.title2.weight(.semibold))
                Text("We'll read it and consider it for a future update.").foregroundStyle(.secondary)
                Text("Reference: \(reference)").font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                Spacer()
                HStack {
                    Button("Write Another") { draft.startAnother(); textFocused = true }
                    Spacer()
                    Button("Done", action: close).keyboardShortcut(.defaultAction)
                }
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Your request").font(.headline)
                    ZStack(alignment: .topLeading) {
                        if draft.prompt.isEmpty {
                            Text("I'd love Daydreaming to…").foregroundStyle(.tertiary).padding(9).allowsHitTesting(false)
                        }
                        TextEditor(text: $draft.prompt).focused($textFocused)
                            .scrollContentBackground(.hidden).padding(5)
                            .accessibilityLabel("Your feature request").disabled(draft.isSending)
                    }
                    .frame(minHeight: 130, maxHeight: .infinity)
                    .background(.background, in: .rect(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                    Text("Only this form and the app version are sent. Your pictures and wallpaper idea stay private.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Name or handle").font(.callout)
                        VStack(alignment: .leading, spacing: 5) {
                            TextField("Optional", text: $draft.name).textFieldStyle(.roundedBorder).disabled(draft.isSending)
                                .accessibilityLabel("Name or handle for public credit, optional")
                            Text("Your name may appear in release notes.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    GridRow {
                        Text("Email").font(.callout)
                        VStack(alignment: .leading, spacing: 5) {
                            TextField("Optional", text: $draft.email).textFieldStyle(.roundedBorder).disabled(draft.isSending)
                                .accessibilityLabel("Email for a private reply, optional")
                            Text("Your email is only for a reply.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let error = draft.error { Text(error).font(.callout).foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently) }
                HStack {
                    Spacer()
                    Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                    Button { draft.submit() } label: {
                        HStack(spacing: 6) {
                            if draft.isSending { ProgressView().controlSize(.small) }
                            Text(draft.isSending ? "Sending…" : "Send request")
                        }
                    }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
                    .disabled(draft.isSending || draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(.horizontal, 26).padding(.bottom, 22).padding(.top, 8)
        .background {
            LogoBackdrop(isActive: false, inertia: .init())
                .ignoresSafeArea(.container, edges: .top)
        }
        .onAppear { textFocused = true }
        .onKeyPress(.escape) { close(); return .handled }
        .onDrop(of: [.fileURL], isTargeted: nil) { _ in true }
    }
}

@MainActor
@Observable
final class AboutDetails { var showAddress = false }

struct DaydreamingAboutView: View {
    @Bindable var details: AboutDetails
    let close: () -> Void
    @State private var copiedAddress = false
    private let address = "Spatie\nKruikstraat 22, Box 12\n2018 Antwerp\nBelgium"
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "Version \(info["CFBundleShortVersionString"] as? String ?? "0.1.0") (\(info["CFBundleVersion"] as? String ?? "0"))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 9) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 92, height: 92)
                    Text("Daydreaming").font(.system(size: 34, weight: .medium, design: .serif))
                    Text(version).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Link("getdaydreaming.com", destination: URL(string: "https://getdaydreaming.com")!).font(.callout)
                }
                .frame(maxWidth: .infinity).padding(.top, 42).padding(.bottom, 25)
                .background {
                    LogoBackdrop(isActive: false, inertia: .init())
                        .ignoresSafeArea(.container, edges: .top)
                }
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Made by").foregroundStyle(.secondary)
                        Link("SPATIE", destination: URL(string: "https://spatie.be")!)
                            .font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(.primary)
                        Spacer()
                        Text("Antwerp, Belgium").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("A favorite picture, reimagined through the day. Built by Spatie, free for anyone who wants it.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack(spacing: 22) {
                        product("Flare", resource: "MakerFlare", host: "flareapp.io")
                        product("Mailcoach", resource: "MakerMailcoach", host: "mailcoach.app")
                        product("There There", resource: "MakerThereThere", host: "there-there.app")
                    }.frame(maxWidth: .infinity)
                    Divider()
                    HStack(alignment: .top, spacing: 14) {
                        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                            .padding(9).background(.background)
                            .overlay(Rectangle().stroke(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 3])))
                            .rotationEffect(.degrees(-7)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Daydreaming is postcardware").font(.headline)
                            Text("Free to use. If it brightens your day, we'd love a postcard from your hometown.")
                                .font(.callout).foregroundStyle(.secondary)
                            Button(details.showAddress ? "Hide address" : "Where to send one") { details.showAddress.toggle() }
                                .buttonStyle(.link)
                        }
                    }
                    if details.showAddress {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(address).font(.callout).textSelection(.enabled)
                            HStack {
                                Button(copiedAddress ? "Copied" : "Copy Address") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(address, forType: .string)
                                    copiedAddress = true
                                }
                                Spacer()
                                Link("The postcard wall", destination: URL(string: "https://spatie.be/open-source/postcards")!)
                            }
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary, in: .rect(cornerRadius: 10))
                    }
                    Divider()
                    HStack {
                        Button(AppCopy.askForAFeature) { CommunityWindowController.showSubmission() }.buttonStyle(.link)
                        Spacer()
                        Link("spatie.be", destination: URL(string: "https://spatie.be")!).foregroundStyle(.secondary)
                    }.font(.callout)
                }.padding(26)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(nsColor: .windowBackgroundColor))
        .onKeyPress(.escape) { close(); return .handled }
    }

    private func product(_ title: String, resource: String, host: String) -> some View {
        Link(destination: URL(string: "https://\(host)")!) {
            VStack(spacing: 7) {
                BundledCommunityImage(resource: resource, fileExtension: "png").scaledToFit().frame(width: 32, height: 32)
                Text(title).font(.caption.weight(.medium))
            }.frame(maxWidth: .infinity)
        }.foregroundStyle(.primary).help("\(title) · \(host)")
    }
}

/// NSImage resolves bundled files explicitly; SwiftUI's named initializer expects an asset catalog.
struct BundledCommunityImage: View {
    let resource: String
    let fileExtension: String
    private var image: NSImage? {
        Bundle.main.url(forResource: resource, withExtension: fileExtension).flatMap { NSImage(contentsOf: $0) }
    }
    var body: some View {
        if let image { Image(nsImage: image).resizable() }
    }
}
