import SwiftUI
import SkedCore

/// The group list from the server, shared by onboarding and the profile.
@MainActor
@Observable
final class GroupList {
    enum State {
        case loading
        case loaded
        case failed(APIError)
    }

    private(set) var state: State = .loading
    private(set) var groups: [GroupInfo] = []

    func load(client: APIClient) async {
        state = .loading
        do {
            groups = try await client.groups()
            state = .loaded
        } catch {
            state = .failed(error as? APIError ?? .badResponse)
        }
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ProfileDraft()
    @State private var groupList = GroupList()
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

                Section(L("profile.group")) {
                    GroupRow(selection: $draft.group, list: groupList)
                }

                Section {
                    SubgroupPicker(selection: $draft.subgroup)
                } header: {
                    Text(L("profile.subgroup"))
                } footer: {
                    Text(L("subgroup.footer"))
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
                .disabled(draft.group == nil)
                .padding()
                .accessibilityIdentifier("onboarding.save")
            }
            .task {
                await groupList.load(client: model.client)
            }
        }
    }

    private func save() {
        attemptedSave = true
        switch draft.validate(availableGroups: groupList.groups) {
        case .success(let profile):
            model.save(profile: profile)
        case .failure(.emptyName):
            nameFocused = true
        case .failure:
            draft.group = nil
        }
    }
}

/// "Группа: ИСП-225а ›" that opens the searchable list, or the load state.
struct GroupRow: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: String?
    var list: GroupList

    var body: some View {
        switch list.state {
        case .loading:
            ProgressView()
        case .failed(let error):
            VStack(alignment: .leading, spacing: 6) {
                Text(error.errorDescription ?? "")
                    .font(.subheadline.weight(.semibold))
                Text(error.recoverySuggestion ?? "")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(L("action.retry")) {
                    Task { await list.load(client: model.client) }
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("retry")
            }
        case .loaded:
            NavigationLink {
                GroupPickerView(groups: list.groups, selection: $selection)
            } label: {
                LabeledContent(L("profile.group"), value: selection ?? L("onboarding.choose"))
            }
            .accessibilityIdentifier("onboarding.group")
        }
    }
}

/// Searchable list of all groups, sectioned by course.
struct GroupPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let groups: [GroupInfo]
    @Binding var selection: String?
    @State private var search = ""

    private var filtered: [GroupInfo] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return groups }
        return groups.filter { $0.name.localizedStandardContains(query) }
    }

    var body: some View {
        let sections = Dictionary(grouping: filtered, by: \.course).sorted { $0.key < $1.key }
        List {
            ForEach(sections, id: \.key) { course, groups in
                Section(course > 0 ? L("course.label \(course)") : L("course.other")) {
                    ForEach(groups) { group in
                        Button {
                            selection = group.name
                            dismiss()
                        } label: {
                            HStack {
                                Text(group.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if group.name == selection {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .accessibilityAddTraits(group.name == selection ? .isSelected : [])
                    }
                }
            }
        }
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: L("group.search"))
        .navigationTitle(L("profile.group"))
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
