import Foundation

enum PromptRenderer {
    static func editableText(_ template: String) -> String {
        template.replacingOccurrences(of: "{{time}}", with: "the time of day")
            .replacingOccurrences(of: "{{date}}", with: "today")
            .replacingOccurrences(of: "{{weather}}", with: "the local weather")
    }

    static func renderHour(_ template: String, date: Date, weather: String, style: WallpaperStyle = .natural, appearance: WallpaperAppearance? = nil) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let rendered = template.replacingOccurrences(of: "{{time}}", with: time)
            .replacingOccurrences(of: "{{date}}", with: date.formatted(date: .complete, time: .omitted))
            .replacingOccurrences(of: "{{weather}}", with: weather)
        let styleNote = style == .natural ? "" : "\n\n" + style.prompt(extraInstructions: "")
        let appearanceNote = appearance.map { "\n\nmacOS is currently in \($0.title). Use this context when the user asks the picture to follow Light or Dark Mode. Keep the requested time and weather accurate." } ?? ""
        return rendered + styleNote + appearanceNote + "\n\nThe local time is " + time + ", and the weather is " + weather + ". Preserve the composition and main subjects so it remains recognizably the same picture."
    }

    static func renderHour(_ template: String, date: Date, weather: WeatherSnapshot, style: WallpaperStyle = .natural,
                           appearance: WallpaperAppearance? = nil) -> String {
        let prompt = renderHour(template, date: date, weather: weather.label, style: style, appearance: appearance)
        guard let details = weather.details else { return prompt }
        return prompt + "\n\nApple Weather details for this hour: " + details.promptText
    }

    static func render(_ template: String, context: RenderContext) -> String {
        let time = DateFormatter.localizedString(from: context.slotDate, dateStyle: .none, timeStyle: .short)
        let date = DateFormatter.localizedString(from: context.slotDate, dateStyle: .full, timeStyle: .none)

        let rendered = template
            .replacingOccurrences(of: "{{time}}", with: time)
            .replacingOccurrences(of: "{{date}}", with: date)
            .replacingOccurrences(of: "{{weather}}", with: context.weather)

        let contextNote = "The local time is around \(time), and the weather is \(context.weather)."
        if template == CanvasSettings.defaultPrompt {
            let sentence = rendered.hasSuffix(".") ? rendered : rendered + "."
            return "\(sentence) \(contextNote) Preserve the composition, main subjects, and style so it remains recognizably the same image."
        }

        return "\(rendered)\n\n\(contextNote)"
    }
}
