import Foundation

public enum Subgroup: Int, Codable, CaseIterable, Sendable {
    case unspecified = 0
    case first = 1
    case second = 2
}

/// The student's profile. Stored only on the device. There is no building:
/// groups move between buildings from day to day, so it comes with each pair.
public struct Profile: Codable, Equatable, Sendable {
    public var fullName: String
    public var group: String
    /// Derived from the group number, e.g. "ИСП-324а" → 3.
    public var course: Int
    public var subgroup: Subgroup

    public init(fullName: String, group: String, course: Int, subgroup: Subgroup) {
        self.fullName = fullName
        self.group = group
        self.course = course
        self.subgroup = subgroup
    }
}

/// Onboarding input before it becomes a `Profile`.
public struct ProfileDraft: Equatable, Sendable {
    public var fullName = ""
    public var group: String?
    public var subgroup: Subgroup = .unspecified

    public init() {}

    public enum Problem: Error, Equatable, Sendable {
        case emptyName, noGroup, unknownGroup
    }

    /// Validates against the group list the server returned.
    public func validate(availableGroups: [GroupInfo]) -> Result<Profile, Problem> {
        let name = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .failure(.emptyName) }
        guard let group else { return .failure(.noGroup) }
        guard let info = availableGroups.first(where: { $0.name == group }) else {
            return .failure(.unknownGroup)
        }
        return .success(Profile(fullName: name, group: group, course: info.course, subgroup: subgroup))
    }
}

/// Where the schedule server lives. Fixed for users; UI tests point the app
/// at a local server through the `SKED_SERVER_URL` launch environment.
public enum Server {
    public static let production = URL(string: "https://lunars.ru")!

    public static func baseURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        guard let raw = environment["SKED_SERVER_URL"], let url = URL(string: raw),
              let scheme = url.scheme, ["http", "https"].contains(scheme), url.host() != nil else {
            return production
        }
        return url
    }
}
