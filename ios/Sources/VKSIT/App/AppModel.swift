import Foundation
import Observation
import VKSITCore

/// App-wide state: the local profile, server address and the schedule.
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
    private(set) var server: ServerAddress
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
        static let server = "server"
    }

    init(defaults: UserDefaults = .standard, cache: ScheduleCache = ScheduleCache()) {
        self.defaults = defaults
        self.cache = cache
        profile = defaults.data(forKey: Keys.profile).flatMap { try? JSONDecoder().decode(Profile.self, from: $0) }
        server = defaults.data(forKey: Keys.server).flatMap { try? JSONDecoder().decode(ServerAddress.self, from: $0) } ?? .default
        if let profile, let (cached, fetchedAt) = cache.load(building: profile.building, group: profile.group) {
            scheduleState = .loaded(cached)
            dataFetchedAt = fetchedAt
        }
    }

    var client: APIClient { APIClient(address: server) }

    var schedule: ScheduleResponse? {
        if case .loaded(let response) = scheduleState { return response }
        return nil
    }

    var query: ScheduleQuery? {
        guard let profile, let schedule else { return nil }
        return ScheduleQuery(days: schedule.days, group: profile.group, subgroup: profile.subgroup)
    }

    func save(profile: Profile) {
        let groupChanged = profile.group != self.profile?.group || profile.building != self.profile?.building
        self.profile = profile
        defaults.set(try? JSONEncoder().encode(profile), forKey: Keys.profile)
        if groupChanged {
            scheduleState = .idle
            dataFetchedAt = nil
            staleReason = nil
            if let (cached, fetchedAt) = cache.load(building: profile.building, group: profile.group) {
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

    /// Applies a new server address to all following requests immediately.
    func save(server: ServerAddress) {
        guard server != self.server else { return }
        self.server = server
        defaults.set(try? JSONEncoder().encode(server), forKey: Keys.server)
    }

    /// Downloads the schedule; on failure keeps showing the cached snapshot.
    func refresh() async {
        guard let profile, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if schedule == nil { scheduleState = .loading }

        do {
            let (response, data) = try await client.schedule(building: profile.building, group: profile.group)
            // The profile may have changed while the request was in flight.
            guard profile == self.profile else { return }
            let now = Date.now
            cache.save(data, building: profile.building, group: profile.group, at: now)
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
