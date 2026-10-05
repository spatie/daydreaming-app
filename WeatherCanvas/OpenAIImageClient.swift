import Foundation

struct OpenAIImageClient {
    func edit(
        sourceURL: URL,
        prompt: String,
        apiKey: String,
        model: ImageModel,
        quality: ImageQuality,
        size: String
    ) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/edits")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
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

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ImageClientError.invalidResponse
        }

        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorResponse.self, from: data).error.message)
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
    struct Detail: Decodable { let message: String }
    let error: Detail
}

enum ImageClientError: LocalizedError {
    case invalidResponse
    case missingImage
    case api(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The image provider sent an invalid response."
        case .missingImage: "The image provider returned no image."
        case .api(let message): message
        }
    }
}
