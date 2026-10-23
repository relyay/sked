import Foundation
import Observation
import SkedCore

/// App-wide state: the local profile and the schedule.
@MainActor
@Observable
final class AppModel {
    enum ScheduleState {
        case idle
        case loading
        case loaded(ScheduleResponse)
        /// Network failed and there is no cached snapshot.
        case failed(APIError)
    }

    private(set) var profile: Profile?
    private(set) var scheduleState: ScheduleState = .idle
    /// When the shown schedule was downloaded.
    private(set) var dataFetchedAt: Date?
    /// Set when the shown schedule came from the offline cache.
    private(set) var staleReason: APIError?
    private(set) var isRefreshing = false

    private let defaults: UserDefaults
    private let cache: ScheduleCache

    private enum Keys {
        static let profile = "profile"
        /// Left over from builds with a configurable server address.
        static let legacyServer = "server"
    }

    private let baseURL: URL

    init(defaults: UserDefaults = .standard, cache: ScheduleCache = ScheduleCache(), baseURL: URL = Server.baseURL()) {
        self.defaults = defaults
        self.cache = cache
        self.baseURL = baseURL
        defaults.removeObject(forKey: Keys.legacyServer)
        profile = defaults.data(forKey: Keys.profile).flatMap { try? JSONDecoder().decode(Profile.self, from: $0) }
        if let profile, let (cached, fetchedAt) = cache.load(group: profile.group) {
            scheduleState = .loaded(cached)
            dataFetchedAt = fetchedAt
        }
    }

    var client: APIClient { APIClient(baseURL: baseURL) }

    var schedule: ScheduleResponse? {
        if case .loaded(let response) = scheduleState { return response }
        return nil
    }

    var query: ScheduleQuery? {
        guard let profile, let schedule else { return nil }
        return ScheduleQuery(days: schedule.days, group: profile.group, subgroup: profile.subgroup)
    }

    func save(profile: Profile) {
        let groupChanged = profile.group != self.profile?.group
        self.profile = profile
        defaults.set(try? JSONEncoder().encode(profile), forKey: Keys.profile)
        if groupChanged {
            scheduleState = .idle
            dataFetchedAt = nil
            staleReason = nil
            if let (cached, fetchedAt) = cache.load(group: profile.group) {
                scheduleState = .loaded(cached)
                dataFetchedAt = fetchedAt
            }
            Task { await refresh() }
        }
    }

    func resetProfile() {
        profile = nil
        defaults.removeObject(forKey: Keys.profile)
        cache.removeAll()
        scheduleState = .idle
        dataFetchedAt = nil
        staleReason = nil
    }


    /// Downloads the schedule; on failure keeps showing the cached snapshot.
    func refresh() async {
        guard let profile, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if schedule == nil { scheduleState = .loading }

        do {
            let (response, data) = try await client.schedule(group: profile.group)
            // The profile may have changed while the request was in flight.
            guard profile == self.profile else { return }
            let now = Date.now
            cache.save(data, group: profile.group, at: now)
            scheduleState = .loaded(response)
            dataFetchedAt = now
            staleReason = nil
        } catch is CancellationError {
            return
        } catch {
            guard profile == self.profile else { return }
            let apiError = error as? APIError ?? .badResponse
            if schedule != nil {
                staleReason = apiError
            } else {
                scheduleState = .failed(apiError)
            }
        }
    }
}
