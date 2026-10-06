import Foundation

struct OpenAIImageClient {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let transport: Transport

    init(transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }) {
        self.transport = transport
    }

    func edit(
        sourceURL: URL,
        prompt: String,
        apiKey: String,
        model: ImageModel,
        quality: ImageQuality,
        size: String,
        willSend: @escaping @MainActor () async throws -> Void = {},
        didReject: @escaping @MainActor (Int) -> Void = { _ in }
    ) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/edits")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = "Daydreaming-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try body(
            boundary: boundary,
            sourceURL: sourceURL,
            fields: [
                "model": model.rawValue,
                "prompt": prompt,
                "quality": quality.rawValue,
                "size": size,
                "output_format": "png",
                "n": "1",
            ]
        )

        try await willSend()
        let (data, response) = try await transport(request)
        guard let response = response as? HTTPURLResponse else {
            throw ImageClientError.invalidResponse
        }

        guard (200..<300).contains(response.statusCode) else {
            if (400..<500).contains(response.statusCode) { await didReject(response.statusCode) }
            let error = try? JSONDecoder().decode(APIErrorResponse.self, from: data).error
            if response.statusCode == 401 { throw ImageClientError.invalidKey }
            if error?.code == "insufficient_quota" || error?.code == "billing_hard_limit_reached" {
                throw ImageClientError.billing
            }
            let message = error?.message
                ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            throw ImageClientError.api(message)
        }

        let result = try JSONDecoder().decode(ImageEditResponse.self, from: data)
        guard let encoded = result.data.first?.b64JSON,
              let image = Data(base64Encoded: encoded) else {
            throw ImageClientError.missingImage
        }

        return image
    }

    private func body(boundary: String, sourceURL: URL, fields: [String: String]) throws -> Data {
        var data = Data()

        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            data.append(Data("--\(boundary)\r\n".utf8))
            data.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            data.append(Data("\(value)\r\n".utf8))
        }

        data.append(Data("--\(boundary)\r\n".utf8))
        data.append(Data("Content-Disposition: form-data; name=\"image[]\"; filename=\"source.jpg\"\r\n".utf8))
        data.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        data.append(try Data(contentsOf: sourceURL))
        data.append(Data("\r\n--\(boundary)--\r\n".utf8))

        return data
    }
}

private struct ImageEditResponse: Decodable {
    struct Item: Decodable {
        let b64JSON: String?

        enum CodingKeys: String, CodingKey {
            case b64JSON = "b64_json"
        }
    }

    let data: [Item]
}

private struct APIErrorResponse: Decodable {
    struct Detail: Decodable { let message: String; let code: String? }
    let error: Detail
}

enum ImageClientError: LocalizedError {
    case invalidResponse
    case missingImage
    case api(String)
    case invalidKey
    case billing

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The image provider sent an invalid response."
        case .missingImage: "The image provider returned no image."
        case .api(let message): message
        case .invalidKey: "OpenAI couldn't accept your API key. Replace it in Settings, then try again."
        case .billing: "Check your OpenAI credit and billing limit before creating another image. Your current wallpaper stays in place."
        }
    }
}
