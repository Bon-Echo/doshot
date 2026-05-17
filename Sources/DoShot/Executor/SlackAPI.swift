import Foundation

/// Slack API helpers used by onboarding (auth.test + conversations.list).
/// The actual file-upload action happens inside the Claude directive at runtime.
struct SlackAPI {
    enum APIError: Error, LocalizedError {
        case http(Int)
        case slack(String)
        case malformed

        var errorDescription: String? {
            switch self {
            case .http(let code): return "Slack HTTP \(code)"
            case .slack(let code): return "Slack: \(code)"
            case .malformed: return "Unexpected Slack response"
            }
        }
    }

    struct AuthTest: Decodable {
        let ok: Bool
        let error: String?
        let team: String?
        let user: String?
    }

    struct Channel: Decodable, Identifiable {
        let id: String
        let name: String
        let isPrivate: Bool?
        let isMember: Bool?

        enum CodingKeys: String, CodingKey {
            case id, name
            case isPrivate = "is_private"
            case isMember = "is_member"
        }
    }

    struct ConversationsList: Decodable {
        let ok: Bool
        let error: String?
        let channels: [Channel]?
    }

    static func authTest(token: String) async throws -> AuthTest {
        let url = URL(string: "https://slack.com/api/auth.test")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw APIError.http(http.statusCode)
        }
        let decoded = try JSONDecoder().decode(AuthTest.self, from: data)
        if !decoded.ok {
            throw APIError.slack(decoded.error ?? "unknown")
        }
        return decoded
    }

    static func conversationsList(token: String) async throws -> [Channel] {
        var components = URLComponents(string: "https://slack.com/api/conversations.list")!
        components.queryItems = [
            URLQueryItem(name: "types", value: "public_channel,private_channel"),
            URLQueryItem(name: "exclude_archived", value: "true"),
            URLQueryItem(name: "limit", value: "200")
        ]
        var req = URLRequest(url: components.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw APIError.http(http.statusCode)
        }
        let decoded = try JSONDecoder().decode(ConversationsList.self, from: data)
        if !decoded.ok {
            throw APIError.slack(decoded.error ?? "unknown")
        }
        return decoded.channels ?? []
    }
}
