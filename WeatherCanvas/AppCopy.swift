/// Shared names keep help and accessibility text aligned with visible actions.
enum AppCopy {
    static let usePictureAndIdeaAsWallpaper = "Use This Picture & Idea as Wallpaper"
    static let previousPictures = "Previous Pictures…"
    static let previousPicturesHelp = "Choose a previous original picture and its saved idea."
    private static let defaultCopy = ImageGenerationCopy(provider: .openAI)
    static let ideaPreviewNotice = defaultCopy.ideaPreviewNotice
    static let ideaHelp = defaultCopy.ideaHelp
    static let previewTimeHelp = defaultCopy.previewTimeHelp
    static let historyChoiceNotice = defaultCopy.historyChoiceNotice
    static func cropDoneNotice(hasChanges: Bool) -> String { defaultCopy.cropDoneNotice(hasChanges: hasChanges) }
}

struct ImageGenerationCopy {
    let provider: ImageDriverDescriptor?
    private var name: String { provider?.name ?? "your image provider" }
    private var credit: String { provider?.creditName ?? "your image provider's credit" }
    var ideaPreviewNotice: String { "After you stop typing, your picture and idea go to \(name) for a preview. New images use credit." }
    var ideaHelp: String { "Describe the feeling or changes you want. Daydreaming adds time and local weather. Making a preview sends your picture, idea, and included text to \(name). New images use \(credit)." }
    var previewTimeHelp: String { "After you stop moving the slider, Daydreaming makes a preview for that hour using \(credit). Your desktop keeps following the current time." }
    var historyChoiceNotice: String { "Reuses a saved preview or makes one using \(credit). Your desktop stays unchanged." }
    func cropDoneNotice(hasChanges: Bool) -> String {
        hasChanges
            ? "Done saves the crop and makes a preview using \(credit). Your desktop stays unchanged."
            : "Done closes without creating an image or changing your desktop."
    }
}
