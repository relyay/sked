import Foundation

public enum Subgroup: Int, Codable, CaseIterable, Sendable {
    case unspecified = 0
    case first = 1
    case second = 2
}

/// The student's profile. Stored only on the device.
public struct Profile: Codable, Equatable, Sendable {
    public var fullName: String
    public var building: Int
    public var course: Int
    public var group: String
    public var subgroup: Subgroup

    public init(fullName: String, building: Int, course: Int, group: String, subgroup: Subgroup) {
        self.fullName = fullName
        self.building = building
        self.course = course
        self.group = group
        self.subgroup = subgroup
    }
}

/// Onboarding input before it becomes a `Profile`.
public struct ProfileDraft: Equatable, Sendable {
    public var fullName = ""
    public var building: Int?
    public var course: Int?
    public var group: String?
    public var subgroup: Subgroup = .unspecified

    public init() {}

    public enum Problem: Error, Equatable, Sendable {
        case emptyName, noBuilding, noGroup, unknownGroup
    }

    /// Validates against the group list the server returned for `building`.
    public func validate(availableGroups: [GroupInfo]) -> Result<Profile, Problem> {
        let name = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .failure(.emptyName) }
        guard let building else { return .failure(.noBuilding) }
        guard let group else { return .failure(.noGroup) }
        guard let info = availableGroups.first(where: { $0.name == group && $0.building == building }) else {
            return .failure(.unknownGroup)
        }
        return .success(Profile(fullName: name, building: building, course: info.course, group: group, subgroup: subgroup))
    }
}

/// Base address of the schedule server, editable in the profile.
public struct ServerAddress: Codable, Equatable, Sendable {
    public static let `default` = ServerAddress(host: "192.168.1.246", port: 1984)

    public var host: String
    public var port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    public enum Problem: Error, Equatable, Sendable {
        case emptyHost, invalidHost, invalidPort
    }

    public static func validate(host: String, port: String) -> Result<ServerAddress, Problem> {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return .failure(.emptyHost) }
        guard let port = Int(port.trimmingCharacters(in: .whitespaces)), (1...65535).contains(port) else {
            return .failure(.invalidPort)
        }
        let address = ServerAddress(host: host, port: port)
        guard address.baseURL != nil else { return .failure(.invalidHost) }
        return .success(address)
    }

    /// `http://host:port`; a host typed with an explicit scheme keeps it.
    public var baseURL: URL? {
        var host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        var scheme = "http"
        if let range = host.range(of: "://") {
            scheme = String(host[..<range.lowerBound]).lowercased()
            host = String(host[range.upperBound...])
        }
        while host.hasSuffix("/") { host.removeLast() }
        guard ["http", "https"].contains(scheme), !host.isEmpty, !host.contains(where: { $0.isWhitespace || $0 == "/" }) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        return components.url
    }
}
