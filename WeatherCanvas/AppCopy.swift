/// Shared names keep help and accessibility text aligned with visible actions.
enum AppCopy {
    static let usePictureAndIdeaAsWallpaper = "Use This Picture & Idea as Wallpaper"
    static let previousPictures = "Previous Pictures…"
    static let previousPicturesHelp = "Choose a previous original picture and its saved idea."
    private static let defaultCopy = ImageGenerationCopy(provider: .openAI)
    static let ideaHelp = defaultCopy.ideaHelp
    static let previewTimeHelp = defaultCopy.previewTimeHelp
    static let historyChoiceNotice = defaultCopy.historyChoiceNotice
    static func cropDoneNotice(hasChanges: Bool) -> String { defaultCopy.cropDoneNotice(hasChanges: hasChanges) }
}

struct ImageGenerationCopy {
    let provider: ImageDriverDescriptor?
    private var credit: String { provider?.creditName ?? "your image provider's credit" }
    var ideaHelp: String { "Describe how your picture should change. We add the preview time, weather at your chosen location, and whether macOS is in Light or Dark Mode.\n\nFor example: \"Follow the time of day and weather at my chosen location: warm morning light, rain when it rains, and city lights after sunset. Use softer, darker colors in Dark Mode.\"" }
    var previewTimeHelp: String { "After you stop moving the slider, Daydreaming makes a preview for that hour using \(credit). Your desktop keeps following the current time." }
    var historyChoiceNotice: String { "Reuses a saved preview or makes one using \(credit). Your desktop stays unchanged." }
    func cropDoneNotice(hasChanges: Bool) -> String {
        hasChanges
            ? "Done saves the crop and makes a preview using \(credit). Your desktop stays unchanged."
            : "Done closes without creating an image or changing your desktop."
    }
}
