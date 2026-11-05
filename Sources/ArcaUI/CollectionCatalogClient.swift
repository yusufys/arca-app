import Foundation
import ArcaCore

struct CollectionCatalogClient {
    let baseURL: URL
    private static let publicSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 12
        return URLSession(configuration: config)
    }()

    func catalog() async throws -> Data {
        try await request("collection-templates", byteLimit: 3_000_000)
    }

    func prompt(for description: String) async throws -> String {
        let intent = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !intent.isEmpty, intent.unicodeScalars.count <= 2000 else {
            throw CollectionDesignError("Describe your collection in 1 to 2,000 characters.")
        }
        let body = try JSONEncoder().encode(["intent": intent])
        let data = try await request("collection-prompt", body: body, byteLimit: 131_072)
        struct Reply: Decodable { let version: Int; let prompt: String }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        guard reply.version == 1, !reply.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CollectionDesignError("This prompt requires a newer version of Arca.")
        }
        return reply.prompt
    }

    private func request(_ endpoint: String, body: Data? = nil, byteLimit: Int) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/v1").appendingPathComponent(endpoint))
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpMethod = "POST"
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (bytes, response) = try await Self.publicSession.bytes(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CollectionDesignError("Arca could not reach its collection service. Try again in a moment.")
        }
        guard response.expectedContentLength <= byteLimit else { throw CollectionDesignError("The server response is too large.") }
        var data = Data()
        for try await byte in bytes {
            guard data.count < byteLimit else { throw CollectionDesignError("The server response is too large.") }
            data.append(byte)
        }
        return data
    }

    static func templates(in data: Data) throws -> [StarterTemplate] {
        guard data.count <= 3_000_000, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["version"] as? Int == 1, let rows = object["templates"] as? [[String: Any]] else {
            throw CollectionDesignError("This catalog requires a newer version of Arca.")
        }
        var seen = Set<String>()
        return try rows.map { row in
            guard let id = row["id"] as? String, !id.isEmpty, seen.insert(id).inserted,
                  let subtitle = row["subtitle"] as? String, let blueprint = row["schema"] else {
                throw CollectionDesignError("The collection catalog is incomplete.")
            }
            let schema = try CollectionBlueprint.schema(from: blueprint, spaceID: UUID())
            return StarterTemplate(id: id, name: schema.name, subtitle: subtitle,
                                   iconName: schema.iconName, colorHex: schema.colorHex, fields: schema.fields)
        }
    }
}
