import Foundation

/// A pair (or a run of pairs merged into one cell) as served by `GET /schedule`.
public struct Lesson: Codable, Hashable, Sendable, Identifiable {
    public var pair: Int
    /// Last pair of a cell that spans several pairs, e.g. an exam.
    public var pairTo: Int?
    /// "HH:mm", Europe/Moscow.
    public var start: String
    public var end: String?
    public var subject: String
    public var teacher: String?
    public var room: String?
    public var isRemote: Bool
    /// `nil` means the whole group.
    public var subgroup: Int?
    public var note: String?
    /// Set when the PDF had no time for this pair and the server derived it.
    public var timeSource: String?

    public init(
        pair: Int, pairTo: Int? = nil, start: String, end: String? = nil, subject: String,
        teacher: String? = nil, room: String? = nil, isRemote: Bool = false, subgroup: Int? = nil,
        note: String? = nil, timeSource: String? = nil
    ) {
        self.pair = pair
        self.pairTo = pairTo
        self.start = start
        self.end = end
        self.subject = subject
        self.teacher = teacher
        self.room = room
        self.isRemote = isRemote
        self.subgroup = subgroup
        self.note = note
        self.timeSource = timeSource
    }

    public var id: String { "\(pair)-\(subgroup ?? 0)-\(subject)" }

    /// The time is not printed in the PDF and is shown with "≈".
    public var isTimeApproximate: Bool { timeSource != nil }

    /// "2" or "1–6" for merged cells.
    public var pairLabel: String {
        if let pairTo, pairTo != pair { return "\(pair)–\(pairTo)" }
        return "\(pair)"
    }
}

public struct Note: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case startsAt, lunch, other
    }

    public var kind: Kind
    public var text: String
    public var time: String?
    public var endTime: String?
    public var pair: Int?
    public var subgroup: Int?

    public init(kind: Kind, text: String, time: String? = nil, endTime: String? = nil, pair: Int? = nil, subgroup: Int? = nil) {
        self.kind = kind
        self.text = text
        self.time = time
        self.endTime = endTime
        self.pair = pair
        self.subgroup = subgroup
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Unknown kinds from a newer server degrade to `.other`.
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .other
        text = try c.decode(String.self, forKey: .text)
        time = try c.decodeIfPresent(String.self, forKey: .time)
        endTime = try c.decodeIfPresent(String.self, forKey: .endTime)
        pair = try c.decodeIfPresent(Int.self, forKey: .pair)
        subgroup = try c.decodeIfPresent(Int.self, forKey: .subgroup)
    }
}

public struct GroupDay: Codable, Hashable, Sendable {
    public var group: String
    public var lessons: [Lesson]
    public var notes: [Note]?

    public init(group: String, lessons: [Lesson], notes: [Note]? = nil) {
        self.group = group
        self.lessons = lessons
        self.notes = notes
    }
}

public struct Day: Codable, Hashable, Sendable, Identifiable {
    /// "YYYY-MM-DD".
    public var date: String
    public var weekday: String?
    public var building: Int
    public var groups: [GroupDay]

    public init(date: String, weekday: String? = nil, building: Int, groups: [GroupDay]) {
        self.date = date
        self.weekday = weekday
        self.building = building
        self.groups = groups
    }

    public var id: String { date }
}

public struct ScheduleResponse: Codable, Hashable, Sendable {
    public var building: Int
    public var source: String
    public var parsedAt: Date
    public var sourceModified: Date?
    public var days: [Day]

    public init(building: Int, source: String, parsedAt: Date, sourceModified: Date? = nil, days: [Day]) {
        self.building = building
        self.source = source
        self.parsedAt = parsedAt
        self.sourceModified = sourceModified
        self.days = days
    }
}

public struct GroupInfo: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    public var course: Int
    public var building: Int

    public init(name: String, course: Int, building: Int) {
        self.name = name
        self.course = course
        self.building = building
    }

    public var id: String { name }
}

public struct GroupsResponse: Codable, Sendable {
    public var building: Int
    public var groups: [GroupInfo]
}

public struct BuildingInfo: Codable, Hashable, Sendable, Identifiable {
    public var building: Int
    /// "npo" | "spo".
    public var source: String
    public var parsedAt: Date
    public var sourceModified: Date?

    public init(building: Int, source: String, parsedAt: Date, sourceModified: Date? = nil) {
        self.building = building
        self.source = source
        self.parsedAt = parsedAt
        self.sourceModified = sourceModified
    }

    public var id: Int { building }
}

public struct BuildingsResponse: Codable, Sendable {
    public var buildings: [BuildingInfo]
}

public struct Health: Codable, Sendable {
    public struct Source: Codable, Sendable {
        public var source: String
        public var building: Int?
        public var lastSuccess: Date?
        public var lastError: String?
    }

    /// "ok" | "degraded".
    public var status: String
    public var version: String
    public var lastParse: Date?
    public var sources: [Source]
}

public struct APIErrorBody: Codable, Sendable {
    public var error: String
}

extension JSONDecoder {
    /// Decoder for server payloads: Go emits RFC 3339 with nanoseconds.
    public static let vksit: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = parseRFC3339(string) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(string)"))
        }
        return decoder
    }()
}

extension JSONEncoder {
    public static let vksit: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

/// Parses RFC 3339 timestamps with any number of fractional digits.
func parseRFC3339(_ string: String) -> Date? {
    var s = string
    if let dot = s.firstIndex(of: "."),
       let zone = s[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
        // Keep milliseconds; Foundation's parser rejects longer fractions.
        let digits = s[s.index(after: dot)..<zone].prefix(3)
        s = String(s[..<dot]) + "." + digits.padding(toLength: 3, withPad: "0", startingAt: 0) + String(s[zone...])
        return try? Date(s, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
    return try? Date(s, strategy: Date.ISO8601FormatStyle())
}
