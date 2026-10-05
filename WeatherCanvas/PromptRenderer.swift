import Foundation

enum PromptRenderer {
    static func render(_ template: String, context: RenderContext) -> String {
        let time = DateFormatter.localizedString(from: context.slotDate, dateStyle: .none, timeStyle: .short)
        let date = DateFormatter.localizedString(from: context.slotDate, dateStyle: .full, timeStyle: .none)

        let rendered = template
            .replacingOccurrences(of: "{{time}}", with: time)
            .replacingOccurrences(of: "{{date}}", with: date)
            .replacingOccurrences(of: "{{weather}}", with: context.weather)

        let contextNote = "The local time is around \(time), and the weather is \(context.weather)."
        if template == CanvasSettings.defaultPrompt {
            return "\(rendered). \(contextNote) Preserve the composition, main subjects, and style so it remains recognizably the same image."
        }

        return "\(rendered)\n\n\(contextNote)"
    }
}
