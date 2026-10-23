import SwiftUI
import VKSITCore

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmsReset = false

    var body: some View {
        NavigationStack {
            Form {
                if let profile = model.profile {
                    userSection(profile)
                }
                ServerSection()
                dataSection
                Section {
                    LabeledContent(L("profile.version"), value: appVersion)
                }
            }
            .scrollContentBackground(.hidden)
            .background(ScreenBackground())
            .navigationTitle(L("tab.profile"))
            .confirmationDialog(L("profile.resetConfirm"), isPresented: $confirmsReset, titleVisibility: .visible) {
                Button(L("profile.reset"), role: .destructive) { model.resetProfile() }
            } message: {
                Text(L("profile.resetMessage"))
            }
        }
    }

    private func userSection(_ profile: Profile) -> some View {
        Section(L("profile.user")) {
            NavigationLink {
                NameEditor(profile: profile)
            } label: {
                LabeledContent(L("profile.fullName"), value: profile.fullName)
            }
            NavigationLink {
                StudyEditor(profile: profile)
            } label: {
                LabeledContent(L("profile.building"), value: Format.building(profile.building))
            }
            NavigationLink {
                StudyEditor(profile: profile)
            } label: {
                LabeledContent(L("profile.course"), value: L("course.label \(profile.course)"))
            }
            NavigationLink {
                StudyEditor(profile: profile)
            } label: {
                LabeledContent(L("profile.group"), value: profile.group)
            }
            NavigationLink {
                SubgroupEditor(profile: profile)
            } label: {
                LabeledContent(L("profile.subgroup"), value: subgroupName(profile.subgroup))
            }
            Button(L("profile.reset"), role: .destructive) { confirmsReset = true }
        }
    }

    private var dataSection: some View {
        Section {
            LabeledContent(L("profile.dataUpdated")) {
                if let fetchedAt = model.dataFetchedAt {
                    Text(fetchedAt, format: .dateTime.day().month().hour().minute())
                } else {
                    Text(L("profile.never"))
                }
            }
            if let parsedAt = model.schedule?.parsedAt {
                LabeledContent(L("profile.serverParsed"), value: parsedAt.formatted(date: .abbreviated, time: .shortened))
            }
            if let reason = model.staleReason {
                Text(reason.errorDescription ?? "")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Button {
                Task { await model.refresh() }
            } label: {
                HStack {
                    Text(L("profile.refreshNow"))
                    if model.isRefreshing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(model.isRefreshing)
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}

func subgroupName(_ subgroup: Subgroup) -> String {
    switch subgroup {
    case .unspecified: L("subgroup.unspecified")
    case .first, .second: L("subgroup.badge \(subgroup.rawValue)")
    }
}

/// Address/port with validation, applied as soon as it is valid, plus a
/// connection check against `/health`.
struct ServerSection: View {
    @Environment(AppModel.self) private var model
    @State private var host = ""
    @State private var port = ""
    @State private var check: CheckState = .idle

    enum CheckState {
        case idle, checking
        case ok(Health)
        case failed(APIError)
    }

    var body: some View {
        Section {
            TextField(L("server.host"), text: $host)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("server.host")
            TextField(L("server.port"), text: $port)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("server.port")
            if let problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Button(L("server.check")) {
                Task { await runCheck() }
            }
            .disabled(problem != nil)
            checkResult
            Button(L("server.resetDefault")) {
                host = ServerAddress.default.host
                port = String(ServerAddress.default.port)
            }
            .font(.footnote)
        } header: {
            Text(L("profile.server"))
        } footer: {
            Text(L("server.footer"))
        }
        .onAppear {
            host = model.server.host
            port = String(model.server.port)
        }
        .onChange(of: host) { apply() }
        .onChange(of: port) { apply() }
    }

    private var problem: String? {
        switch ServerAddress.validate(host: host, port: port) {
        case .success: nil
        case .failure(.emptyHost): L("server.emptyHost")
        case .failure(.invalidHost): L("server.invalidHost")
        case .failure(.invalidPort): L("server.invalidPort")
        }
    }

    private func apply() {
        check = .idle
        if case .success(let address) = ServerAddress.validate(host: host, port: port) {
            model.save(server: address)
        }
    }

    private func runCheck() async {
        check = .checking
        do {
            check = .ok(try await model.client.health())
        } catch {
            check = .failed(error as? APIError ?? .badResponse)
        }
    }

    @ViewBuilder
    private var checkResult: some View {
        switch check {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView()
        case .ok(let health):
            VStack(alignment: .leading, spacing: 4) {
                Label(health.status == "ok" ? L("server.ok") : L("server.degraded"), systemImage: "circle.fill")
                    .foregroundStyle(health.status == "ok" ? .green : .orange)
                if let lastParse = health.lastParse {
                    Text(L("server.lastParse \(lastParse.formatted(date: .abbreviated, time: .shortened))"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(L("server.version \(health.version)"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        case .failed(let error):
            VStack(alignment: .leading, spacing: 4) {
                Label(error.errorDescription ?? "", systemImage: "circle.fill")
                    .foregroundStyle(.red)
                Text(error.recoverySuggestion ?? "")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

private struct NameEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let profile: Profile
    @State private var name = ""

    var body: some View {
        Form {
            Section {
                TextField(L("onboarding.namePlaceholder"), text: $name)
                    .textContentType(.name)
            } footer: {
                Text(L("onboarding.nameFooter"))
            }
        }
        .navigationTitle(L("profile.fullName"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L("action.save")) {
                    var updated = profile
                    updated.fullName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    model.save(profile: updated)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear { name = profile.fullName }
    }
}

/// Building, course and group are edited together because a group only
/// exists within its building and course.
private struct StudyEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let profile: Profile
    @State private var draft = ProfileDraft()
    @State private var options = StudyOptions()

    var body: some View {
        Form {
            StudySection(draft: $draft, options: options)
        }
        .navigationTitle(L("profile.study"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L("action.save")) {
                    if case .success(let updated) = draft.validate(availableGroups: options.groups) {
                        model.save(profile: updated)
                        dismiss()
                    }
                }
                .disabled(!isValid)
            }
        }
        .onAppear {
            draft.fullName = profile.fullName
            draft.building = profile.building
            draft.course = profile.course
            draft.group = profile.group
            draft.subgroup = profile.subgroup
        }
        .task { await options.loadBuildings(client: model.client) }
    }

    private var isValid: Bool {
        if case .success = draft.validate(availableGroups: options.groups) { return true }
        return false
    }
}

private struct SubgroupEditor: View {
    @Environment(AppModel.self) private var model
    let profile: Profile
    @State private var subgroup = Subgroup.unspecified

    var body: some View {
        Form {
            Section {
                SubgroupPicker(selection: $subgroup)
            } footer: {
                Text(L("subgroup.footer"))
            }
        }
        .navigationTitle(L("profile.subgroup"))
        .onAppear { subgroup = profile.subgroup }
        .onChange(of: subgroup) {
            var updated = profile
            updated.subgroup = subgroup
            model.save(profile: updated)
        }
    }
}
