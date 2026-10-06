/// Shared names keep help and accessibility text aligned with visible actions.
enum AppCopy {
    static let usePictureAndIdeaAsWallpaper = "Use This Picture & Idea as Wallpaper"
    static let previousPictures = "Previous Pictures…"
    static let previousPicturesHelp = "Choose a previous original picture and its saved idea."
    static let ideaPreviewNotice = "Pausing sends your picture and idea to OpenAI. New previews use credit."
    static let ideaHelp = "Describe the feeling or changes you want. Daydreaming adds time and local weather. Making a preview sends your picture, idea, and included text to OpenAI. New images use OpenAI credit."
    static let previewTimeNotice = "Stopping makes a preview. New images use OpenAI credit."
    static let previewTimeHelp = "Stop at an hour to make a preview using OpenAI credit. Your desktop keeps following the current time."
    static let historyChoiceNotice = "Reuses a saved preview or makes one using OpenAI credit. Your desktop stays unchanged."
    static func cropDoneNotice(hasChanges: Bool) -> String {
        hasChanges
            ? "Done saves the crop and makes a preview using OpenAI credit. Your desktop stays unchanged."
            : "Done closes without creating an image or changing your desktop."
    }
}
