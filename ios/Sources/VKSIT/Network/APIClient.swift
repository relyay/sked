import Foundation
import VKSITCore

/// Network failures translated into something a student can act on.
enum APIError: LocalizedError, Equatable {
    case invalidAddress
    case cannotConnect(host: String)
    case timedOut
    case offline
    case notLoadedYet
    case server(status: Int, message: String?)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            L("error.invalidAddress")
        case .cannotConnect(let host):
            L("error.cannotConnect \(host)")
        case .timedOut:
            L("error.timedOut")
        case .offline:
            L("error.offline")
        case .notLoadedYet:
            L("error.notLoadedYet")
        case .server(let status, let message):
            message.map { L("error.serverMessage \(status) \($0)") } ?? L("error.server \(status)")
        case .badResponse:
            L("error.badResponse")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidAddress, .cannotConnect:
            L("error.recovery.checkServer")
        case .offline:
            L("error.recovery.offline")
        case .timedOut, .notLoadedYet, .server, .badResponse:
            L("error.recovery.retryLater")
        }
    }

    /// Worth retrying automatically.
    var isTransient: Bool {
        switch self {
        case .timedOut, .notLoadedYet: true
        case .server(let status, _): status >= 500
        default: false
        }
    }
}

/// Talks to the vksitd server. Conditional requests (ETag → 304) are handled
/// by URLCache because the server sends `Cache-Control: no-cache`.
struct APIClient: Sendable {
    let address: ServerAddress
    var session: URLSession = .vksit
    var maxAttempts = 3

    func health() async throws -> Health {
        try await get("/health")
    }

    /// All groups of both buildings.
    func groups() async throws -> [GroupInfo] {
        let response: GroupsResponse = try await get("/groups")
        return response.groups
    }

    /// The whole known schedule of one group across buildings, as raw bytes
    /// too for the offline cache.
    func schedule(group: String) async throws -> (ScheduleResponse, Data) {
        try await getWithData("/schedule", query: ["group": group])
    }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        try await getWithData(path, query: query).0
    }

    private func getWithData<T: Decodable>(_ path: String, query: [String: String]) async throws -> (T, Data) {
        guard let base = address.baseURL, var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidAddress
        }
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.invalidAddress }

        var attempt = 0
        while true {
            attempt += 1
            do {
                let data = try await fetch(url)
                do {
                    return (try JSONDecoder.vksit.decode(T.self, from: data), data)
                } catch {
                    throw APIError.badResponse
                }
            } catch let error as APIError where error.isTransient && attempt < maxAttempts {
                // Exponential backoff: 0.5 s, 1 s, 2 s…
                try await Task.sleep(for: .milliseconds(500 * (1 << (attempt - 1))))
            }
        }
    }

    private func fetch(_ url: URL) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch let error as URLError {
            throw map(error, host: url.host() ?? address.host)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.badResponse }
        switch http.statusCode {
        case 200..<300:
            return data
        case 503:
            throw APIError.notLoadedYet
        default:
            let message = try? JSONDecoder.vksit.decode(APIErrorBody.self, from: data).error
            throw APIError.server(status: http.statusCode, message: message)
        }
    }

    private func map(_ error: URLError, host: String) -> APIError {
        switch error.code {
        case .timedOut:
            .timedOut
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            .offline
        case .unsupportedURL, .badURL:
            .invalidAddress
        default:
            .cannotConnect(host: host)
        }
    }
}

extension URLSession {
    static let vksit: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = URLCache(memoryCapacity: 4 << 20, diskCapacity: 32 << 20)
        return URLSession(configuration: config)
    }()
}
