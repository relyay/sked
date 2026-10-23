import SwiftUI
import VKSITCore

/// Loads buildings and groups for the study pickers (onboarding and profile).
@MainActor
@Observable
final class StudyOptions {
    enum State {
        case loading
        case loaded
        case failed(APIError)
    }

    private(set) var state: State = .loading
    private(set) var buildings: [BuildingInfo] = []
    private(set) var groups: [GroupInfo] = []
    private(set) var groupsBuilding: Int?

    func loadBuildings(client: APIClient) async {
        state = .loading
        do {
            buildings = try await client.buildings()
            state = .loaded
        } catch {
            state = .failed(error as? APIError ?? .badResponse)
        }
    }

    func loadGroups(building: Int, client: APIClient) async {
        guard groupsBuilding != building else { return }
        state = .loading
        groups = []
        do {
            groups = try await client.groups(building: building)
            groupsBuilding = building
            state = .loaded
        } catch {
            state = .failed(error as? APIError ?? .badResponse)
        }
    }

    var courses: [Int] {
        Array(Set(groups.map(\.course))).sorted()
    }

    func groups(course: Int?) -> [GroupInfo] {
        groups.filter { course == nil || $0.course == course }
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ProfileDraft()
    @State private var options = StudyOptions()
    @State private var showsServerSettings = false
    @State private var attemptedSave = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("onboarding.namePlaceholder"), text: $draft.fullName)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .focused($nameFocused)
                        .accessibilityIdentifier("onboarding.name")
                    if attemptedSave, draft.fullName.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(L("onboarding.nameRequired"))
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text(L("profile.fullName"))
                } footer: {
                    Text(L("onboarding.nameFooter"))
                }

                StudySection(draft: $draft, options: options)

                Section(L("profile.subgroup")) {
                    SubgroupPicker(selection: $draft.subgroup)
                }

                Section {
                    Button {
                        showsServerSettings = true
                    } label: {
                        LabeledContent(L("profile.server"), value: "\(model.server.host):\(model.server.port)")
                    }
                    .accessibilityIdentifier("onboarding.server")
                }
            }
            .scrollContentBackground(.hidden)
            .background(ScreenBackground())
            .navigationTitle(L("onboarding.title"))
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Text(L("onboarding.save"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .disabled(!canSave)
                .padding()
                .accessibilityIdentifier("onboarding.save")
            }
            .sheet(isPresented: $showsServerSettings) {
                NavigationStack {
                    Form { ServerSection() }
                        .navigationTitle(L("profile.server"))
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(L("action.done")) { showsServerSettings = false }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
            .task(id: model.server) {
                draft.building = nil
                draft.group = nil
                await options.loadBuildings(client: model.client)
                if options.buildings.count == 1 { draft.building = options.buildings[0].building }
            }
        }
    }

    private var canSave: Bool {
        if case .success = draft.validate(availableGroups: options.groups) { return true }
        // Keep the button tappable for an empty name so the hint can appear.
        return draft.group != nil && draft.fullName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        attemptedSave = true
        switch draft.validate(availableGroups: options.groups) {
        case .success(let profile):
            model.save(profile: profile)
        case .failure(.emptyName):
            nameFocused = true
        case .failure:
            break
        }
    }
}

/// Building → course → group, filled from the server.
struct StudySection: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: ProfileDraft
    var options: StudyOptions

    var body: some View {
        Section(L("profile.study")) {
            switch options.state {
            case .failed(let error):
                VStack(alignment: .leading, spacing: 6) {
                    Text(error.errorDescription ?? "")
                        .font(.subheadline.weight(.semibold))
                    Text(error.recoverySuggestion ?? "")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button(L("action.retry")) {
                        Task {
                            if let building = draft.building, !options.buildings.isEmpty {
                                await options.loadGroups(building: building, client: model.client)
                            } else {
                                await options.loadBuildings(client: model.client)
                            }
                        }
                    }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("retry")
                }
            case .loading where options.buildings.isEmpty:
                ProgressView()
            default:
                Picker(L("profile.building"), selection: $draft.building) {
                    Text(L("onboarding.choose")).tag(Int?.none)
                    ForEach(options.buildings) { b in
                        Text("\(Format.building(b.building)) · \(Format.sourceName(b.source))").tag(Int?.some(b.building))
                    }
                }
                .accessibilityIdentifier("onboarding.building")

                if draft.building != nil {
                    if case .loading = options.state {
                        ProgressView()
                    } else {
                        Picker(L("profile.course"), selection: $draft.course) {
                            Text(L("onboarding.allCourses")).tag(Int?.none)
                            ForEach(options.courses, id: \.self) { course in
                                Text(L("course.label \(course)")).tag(Int?.some(course))
                            }
                        }
                        .accessibilityIdentifier("onboarding.course")

                        Picker(L("profile.group"), selection: $draft.group) {
                            Text(L("onboarding.choose")).tag(String?.none)
                            ForEach(options.groups(course: draft.course)) { group in
                                Text(group.name).tag(String?.some(group.name))
                            }
                        }
                        .pickerStyle(.navigationLink)
                        .accessibilityIdentifier("onboarding.group")
                    }
                }
            }
        }
        .task(id: draft.building) {
            guard let building = draft.building else { return }
            await options.loadGroups(building: building, client: model.client)
            if let group = draft.group, !options.groups.contains(where: { $0.name == group }) {
                draft.group = nil
            }
        }
        .onChange(of: draft.course) {
            if let group = draft.group, let course = draft.course,
               options.groups.first(where: { $0.name == group })?.course != course {
                draft.group = nil
            }
        }
        .onChange(of: draft.group) {
            if let group = draft.group, let info = options.groups.first(where: { $0.name == group }) {
                draft.course = info.course
            }
        }
    }
}

struct SubgroupPicker: View {
    @Binding var selection: Subgroup

    var body: some View {
        Picker(L("profile.subgroup"), selection: $selection) {
            Text("1").tag(Subgroup.first)
            Text("2").tag(Subgroup.second)
            Text(L("subgroup.unspecified")).tag(Subgroup.unspecified)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("onboarding.subgroup")
    }
}
