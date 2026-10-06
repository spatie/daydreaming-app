import AppKit
import SwiftUI

/// The screen-shaped frame stays put. The normalized crop describes the original
/// pixels that move beneath it, so saving never depends on the window's size.
struct CropPictureView: View {
    let sourceURL: URL
    var screenAspectRatio: CGFloat = {
        let size = NSScreen.main?.frame.size ?? CGSize(width: 16, height: 9)
        return size.width / size.height
    }()
    var showsActions = true
    var showsControls = true
    var onSelectionChange: ((PictureCrop) -> Void)? = nil
    var onBaselineChange: ((PictureCrop) -> Void)? = nil
    var onImageSizeChange: ((CGSize) -> Void)? = nil
    var initialCrop: PictureCrop? = nil
    var onClose: (@MainActor () -> Void)? = nil
    var usesSubtleBackdrop = true
    let onSave: @MainActor (PictureCrop) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var image: CGImage?
    @State private var selection = PictureCrop.original
    @State private var baseline: PictureCrop?
    @State private var openingCrop: PictureCrop?
    @State private var gestureStart: PictureCrop?
    @State private var pinchStart: PictureCrop?
    @State private var zooming = false
    @State private var adjustingExternally = false
    @State private var adjustmentRevision = UUID()
    @State private var isSaving = false
    @State private var error: String?
    @FocusState private var pictureFocused: Bool

    private var imageSize: CGSize {
        image.map { CGSize(width: $0.width, height: $0.height) } ?? CGSize(width: 16, height: 9)
    }
    private var aspectRatio: CGFloat {
        screenAspectRatio.isFinite && screenAspectRatio > 0 ? screenAspectRatio : 16.0 / 9.0
    }
    private var isEditing: Bool { gestureStart != nil || pinchStart != nil || zooming || adjustingExternally }
    private var hasChanges: Bool { baseline.map { !selection.matchesFraming($0) } ?? false }

    var body: some View {
        VStack(spacing: 0) {
            workspace.frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    if image != nil, let error {
                        Text(error).font(.callout).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12).background(Color(nsColor: .windowBackgroundColor))
                            .padding(16)
                    }
                }
            if showsControls {
                VStack(alignment: .leading, spacing: 8) {
                    if showsActions {
                        Text(AppCopy.cropDoneNotice(hasChanges: hasChanges))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    controls
                }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(.bar)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(isSaving)
        .onChange(of: selection) { _, crop in
            if image != nil { onSelectionChange?(crop) }
        }
        .onChange(of: initialCrop) { _, crop in
            guard image != nil, let crop else { return }
            let constrained = crop.constrained(imageSize: imageSize, targetAspectRatio: aspectRatio, usesOriginalRatio: false)
            if !constrained.matchesFraming(selection) {
                selection = constrained
                adjustingExternally = true
                adjustmentRevision = UUID()
            }
        }
        .onChange(of: screenAspectRatio) { _, _ in
            guard image != nil else { return }
            let wasEdited = hasChanges
            let settled = PictureCrop.editingBaseline(savedCrop: openingCrop, imageSize: imageSize,
                                                       displayAspectRatio: aspectRatio)
            baseline = settled
            onBaselineChange?(settled)
            selection = wasEdited
                ? selection.constrained(imageSize: imageSize, targetAspectRatio: aspectRatio, usesOriginalRatio: false)
                : settled
        }
        .task(id: adjustmentRevision) {
            guard adjustingExternally else { return }
            do { try await Task.sleep(for: .milliseconds(220)) }
            catch { return }
            adjustingExternally = false
        }
        .task(id: sourceURL) {
            image = nil
            error = nil
            gestureStart = nil
            pinchStart = nil
            do {
                let url = sourceURL
                let loadedImage = try await Task.detached(priority: .userInitiated) { try ImageStore.orientedImage(from: url) }.value
                try Task.checkCancellation()
                image = loadedImage
                onImageSizeChange?(imageSize)
                openingCrop = initialCrop
                let settled = PictureCrop.editingBaseline(savedCrop: openingCrop, imageSize: imageSize,
                                                           displayAspectRatio: aspectRatio)
                baseline = settled
                onBaselineChange?(settled)
                selection = settled
                onSelectionChange?(selection)
                pictureFocused = true
            } catch is CancellationError {
            } catch { self.error = error.localizedDescription }
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            Slider(value: Binding(get: {
                selection.controls(imageSize: imageSize, targetAspectRatio: aspectRatio).zoom
            }, set: { zoom in
                let current = selection.controls(imageSize: imageSize, targetAspectRatio: aspectRatio).zoom
                selection = zoomed(selection, by: zoom / current)
            }), in: 1...4, onEditingChanged: { zooming = $0 }) { Text("Zoom") }
                .frame(maxWidth: 220)
                .disabled(image == nil || isSaving)
                .accessibilityLabel("Picture zoom")
                .help("Zoom into your picture. Drag the picture to choose what appears inside the frame.")
            Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            Button("Reset") { reset() }.disabled(image == nil || isSaving)
            Spacer()
            if showsActions {
                Button("Cancel", role: .cancel) { close() }.keyboardShortcut(.cancelAction)
                doneButton
            }
        }
    }

    private var workspace: some View {
        GeometryReader { geometry in
            let available = CGSize(width: max(1, geometry.size.width - 32), height: max(1, geometry.size.height - 24))
            let height = min(available.height, available.width / aspectRatio)
            let frameSize = CGSize(width: height * aspectRatio, height: height)
            let frame = CGRect(x: (geometry.size.width - frameSize.width) / 2,
                               y: (geometry.size.height - frameSize.height) / 2,
                               width: frameSize.width, height: frameSize.height)
            let crop = selection.normalizedRect
            let displayedSize = CGSize(width: frame.width / crop.width, height: frame.height / crop.height)
            ZStack(alignment: .topLeading) {
                (usesSubtleBackdrop ? Color(nsColor: .underPageBackgroundColor) : Color.black)
                if let image {
                    Image(decorative: image, scale: 1).resizable()
                        .frame(width: displayedSize.width, height: displayedSize.height)
                        .position(x: frame.minX + (0.5 - crop.minX) * displayedSize.width,
                                  y: frame.minY + (0.5 - crop.minY) * displayedSize.height)
                    Path { path in
                        path.addRect(CGRect(origin: .zero, size: geometry.size))
                        path.addRoundedRect(in: frame, cornerSize: CGSize(width: 10, height: 10))
                    }
                    .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
                    cropFrame(frame)
                } else if let error {
                    ContentUnavailableView("Picture Unavailable", systemImage: "photo",
                                           description: Text(error))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    WallpaperPreview(url: sourceURL, label: "Your selected picture", fullBleed: true,
                                     softBackdrop: true, displayAspectRatio: aspectRatio)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .background(CropWheelZoom(enabled: image != nil && !isSaving && isEnabled, onZoom: { magnification in
                guard image != nil else { return }
                selection = zoomed(selection, by: magnification)
                adjustingExternally = true
                adjustmentRevision = UUID()
            }))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                guard image != nil else { return }
                if gestureStart == nil { gestureStart = selection }
                selection = (gestureStart ?? selection).moved(by: CGSize(
                    width: -value.translation.width / displayedSize.width,
                    height: -value.translation.height / displayedSize.height))
            }.onEnded { _ in gestureStart = nil })
            .simultaneousGesture(MagnifyGesture().onChanged { value in
                guard image != nil else { return }
                if pinchStart == nil { pinchStart = selection }
                selection = zoomed(pinchStart ?? selection, by: value.magnification)
            }.onEnded { _ in pinchStart = nil })
            .focusable()
            .focused($pictureFocused)
            .focusEffectDisabled(!NSApp.isFullKeyboardAccessEnabled)
            .onKeyPress(.leftArrow) { movePicture(-0.01, 0); return .handled }
            .onKeyPress(.rightArrow) { movePicture(0.01, 0); return .handled }
            .onKeyPress(.upArrow) { movePicture(0, -0.01); return .handled }
            .onKeyPress(.downArrow) { movePicture(0, 0.01); return .handled }
            .onKeyPress("-") { selection = zoomed(selection, by: 0.95); return .handled }
            .onKeyPress("+") { selection = zoomed(selection, by: 1.05); return .handled }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Picture framing")
            .accessibilityValue(cropDescription)
            .accessibilityHint("Drag or use arrow keys to move the picture underneath the fixed screen frame. Pinch, plus, or minus changes zoom.")
            .accessibilityAction(named: "Move Picture Left") { movePicture(-0.02, 0) }
            .accessibilityAction(named: "Move Picture Right") { movePicture(0.02, 0) }
            .accessibilityAction(named: "Move Picture Up") { movePicture(0, -0.02) }
            .accessibilityAction(named: "Move Picture Down") { movePicture(0, 0.02) }
            .accessibilityAction(named: "Zoom In") { selection = zoomed(selection, by: 1.1) }
            .accessibilityAction(named: "Zoom Out") { selection = zoomed(selection, by: 0.9) }
            .help("Drag the picture to frame it for your screen. Pinch to zoom.")
        }
    }

    private func cropFrame(_ frame: CGRect) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.75), lineWidth: 1)
            thirdsGrid.stroke(.white.opacity(0.65), lineWidth: 0.5)
                .opacity(isEditing ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isEditing)
            ForEach(PictureCrop.Corner.allCases) { corner in
                CropCornerMark(corner: corner)
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .square))
                    .frame(width: 16, height: 16)
                    .position(x: corner.isLeft ? 8 : frame.width - 8,
                              y: corner.isTop ? 8 : frame.height - 8)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var thirdsGrid: CropThirdsGrid { CropThirdsGrid() }

    private func zoomed(_ crop: PictureCrop, by magnification: CGFloat) -> PictureCrop {
        guard image != nil, magnification.isFinite, magnification > 0 else { return crop }
        let base = PictureCrop(imageSize: imageSize, targetAspectRatio: aspectRatio).normalizedRect
        return crop.scaled(by: 1 / magnification,
                           minimumSize: CGSize(width: base.width / 4, height: base.height / 4))
    }

    private func movePicture(_ x: CGFloat, _ y: CGFloat) {
        guard image != nil else { return }
        selection = selection.moved(by: CGSize(width: -x * selection.normalizedRect.width,
                                                height: -y * selection.normalizedRect.height))
    }

    private var cropDescription: String {
        let zoom = selection.controls(imageSize: imageSize, targetAspectRatio: aspectRatio).zoom
        return "Zoom \(Double(zoom).formatted(.number.precision(.fractionLength(1)))) times. The frame matches your screen."
    }

    private func reset() {
        selection = PictureCrop(imageSize: imageSize, targetAspectRatio: aspectRatio, usesOriginalRatio: false)
        gestureStart = nil
        pinchStart = nil
    }

    private var doneButton: some View {
        Button { save() } label: {
            if isSaving { ProgressView().controlSize(.small).accessibilityLabel("Saving Crop") }
            else { Text("Done") }
        }
        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        .disabled(image == nil || isSaving)
        .help(AppCopy.cropDoneNotice(hasChanges: hasChanges))
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private func save() {
        guard hasChanges else { close(); return }
        let crop = selection
        isSaving = true
        error = nil
        Task {
            do { try await onSave(crop); close() }
            catch { self.error = error.localizedDescription; isSaving = false }
        }
    }
}

private struct CropThirdsGrid: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            for part in [CGFloat(1.0 / 3), CGFloat(2.0 / 3)] {
                path.move(to: CGPoint(x: rect.width * part, y: 0))
                path.addLine(to: CGPoint(x: rect.width * part, y: rect.height))
                path.move(to: CGPoint(x: 0, y: rect.height * part))
                path.addLine(to: CGPoint(x: rect.width, y: rect.height * part))
            }
        }
    }
}

private struct CropCornerMark: Shape {
    let corner: PictureCrop.Corner

    func path(in rect: CGRect) -> Path {
        let x: CGFloat = corner.isLeft ? rect.minX : rect.maxX
        let y: CGFloat = corner.isTop ? rect.minY : rect.maxY
        return Path { path in
            path.move(to: CGPoint(x: x, y: corner.isTop ? rect.maxY : rect.minY))
            path.addLine(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: corner.isLeft ? rect.maxX : rect.minX, y: y))
        }
    }
}

/// Observe only wheel events inside this artwork, leaving the editor and other windows alone.
private struct CropWheelZoom: NSViewRepresentable {
    let enabled: Bool
    let onZoom: @MainActor (CGFloat) -> Void

    func makeNSView(context: Context) -> WheelView { WheelView() }
    func updateNSView(_ view: WheelView, context: Context) {
        view.enabled = enabled
        view.onZoom = onZoom
    }
    static func dismantleNSView(_ view: WheelView, coordinator: ()) { view.removeMonitor() }

    final class WheelView: NSView {
        var enabled = false
        var onZoom: (@MainActor (CGFloat) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                let handled = MainActor.assumeIsolated {
                    guard let self, self.enabled, let window = self.window, event.window === window,
                          !self.isHiddenOrHasHiddenAncestor,
                          self.bounds.contains(self.convert(event.locationInWindow, from: nil)),
                          event.scrollingDeltaY != 0, let onZoom = self.onZoom else { return false }
                    let sensitivity = event.hasPreciseScrollingDeltas ? 0.01 : 0.06
                    let exponent = min(0.15, max(-0.15, event.scrollingDeltaY * sensitivity))
                    onZoom(CGFloat(exp(exponent)))
                    return true
                }
                return handled ? nil : event
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
