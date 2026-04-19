import Foundation

/// Uploads `.snoroh` packages to the marketplace (`POST /api/upload`).
enum MarketplaceClient {

    struct UploadResult {
        let id: String
        let remaining: Int?
        let packageURL: URL?
    }

    enum UploadError: Error, LocalizedError {
        case invalidURL
        case network(Error)
        case server(code: String, message: String, status: Int)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Marketplace URL is invalid"
            case .network(let e): return "Network error: \(e.localizedDescription)"
            case .server(_, let m, _): return m
            case .invalidResponse: return "Unexpected response from marketplace"
            }
        }
    }

    private struct SuccessResponse: Decodable {
        let id: String
        let remaining: Int?
    }

    private struct ErrorEnvelope: Decodable {
        struct Inner: Decodable {
            let code: String
            let message: String
        }
        let error: Inner
    }

    static func upload(
        data: Data,
        filename: String,
        creator: String?,
        baseURL: String
    ) async throws -> UploadResult {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: trimmedBase) else {
            throw UploadError.invalidURL
        }
        components.path = (components.path.isEmpty ? "" : components.path) + "/api/upload"
        guard let url = components.url else { throw UploadError.invalidURL }

        let boundary = "snoroh-" + UUID().uuidString
        var body = Data()

        func append(_ s: String) {
            if let d = s.data(using: .utf8) { body.append(d) }
        }

        func appendField(name: String, value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }

        appendField(name: "filename", value: filename)
        if let creator, !creator.isEmpty {
            appendField(name: "creator", value: creator)
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: application/json\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 30

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UploadError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UploadError.invalidResponse
        }

        if (200..<300).contains(http.statusCode) {
            guard let ok = try? JSONDecoder().decode(SuccessResponse.self, from: responseData) else {
                throw UploadError.invalidResponse
            }
            var pkgURL: URL?
            if var comps = URLComponents(string: trimmedBase) {
                comps.path = "/p/\(ok.id)"
                pkgURL = comps.url
            }
            return UploadResult(id: ok.id, remaining: ok.remaining, packageURL: pkgURL)
        }

        if let env = try? JSONDecoder().decode(ErrorEnvelope.self, from: responseData) {
            throw UploadError.server(
                code: env.error.code,
                message: env.error.message,
                status: http.statusCode
            )
        }
        throw UploadError.server(
            code: "http_\(http.statusCode)",
            message: "Upload failed (HTTP \(http.statusCode))",
            status: http.statusCode
        )
    }
}
