/// Shared names keep help and accessibility text aligned with visible actions.
enum AppCopy {
    static let usePictureAndIdeaAsWallpaper = "Use This Picture & Idea as Wallpaper"
    static let previousPictures = "Previous Pictures…"
    static let previousPicturesHelp = "Choose a previous original picture and its saved idea."
    static let ideaPreviewNotice = "After you stop typing, your picture and idea go to OpenAI for a preview. New images use credit."
    static let ideaHelp = "Describe the feeling or changes you want. Daydreaming adds time and local weather. Making a preview sends your picture, idea, and included text to OpenAI. New images use OpenAI credit."
    static let previewTimeNotice = "Stop moving the slider to make a preview. New images use OpenAI credit."
    static let previewTimeHelp = "After you stop moving the slider, Daydreaming makes a preview for that hour using OpenAI credit. Your desktop keeps following the current time."
    static let historyChoiceNotice = "Reuses a saved preview or makes one using OpenAI credit. Your desktop stays unchanged."
    static func cropDoneNotice(hasChanges: Bool) -> String {
        hasChanges
            ? "Done saves the crop and makes a preview using OpenAI credit. Your desktop stays unchanged."
            : "Done closes without creating an image or changing your desktop."
    }
}
