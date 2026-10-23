import Foundation
import VKSITCore

/// Last successful `/schedule` response per group, kept on disk
/// for offline use.
///
/// SwiftData would be the natural fit, but its `@Model` macro plugin is not
/// available when cross-compiling with xtool on Linux, so the snapshots are
/// plain JSON files in Application Support.
struct ScheduleCache {
    private struct Entry: Codable {
        var fetchedAt: Date
        var payload: Data
    }

    let directory: URL

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "ScheduleCache", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    func load(group: String) -> (ScheduleResponse, Date)? {
        guard let data = try? Data(contentsOf: url(group: group)),
              let entry = try? JSONDecoder.vksit.decode(Entry.self, from: data),
              let response = try? JSONDecoder.vksit.decode(ScheduleResponse.self, from: entry.payload) else {
            return nil
        }
        return (response, entry.fetchedAt)
    }

    func save(_ payload: Data, group: String, at date: Date) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder.vksit.encode(Entry(fetchedAt: date, payload: payload))
            try data.write(to: url(group: group), options: .atomic)
        } catch {
            // A failed cache write only costs offline availability.
        }
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func url(group: String) -> URL {
        // Group names are Cyrillic with hyphens; percent-encode for a safe file name.
        let name = group.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "group"
        return directory.appending(path: name + ".json")
    }
}
