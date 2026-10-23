import SwiftUI
import VKSITCore

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmsReset = false

    var body: some View {
        NavigationStack {
            Form {
                if let profile = model.profile {
                    Section {
                        NavigationLink {
                            NameEditor(profile: profile)
                        } label: {
                            ProfileCard(profile: profile)
                        }
                    }
                    studySection(profile)
                }
                ServerSection()
                dataSection
                Section(L("profile.about")) {
                    LabeledContent(L("profile.version"), value: appVersion)
                }
                if model.profile != nil {
                    Section {
                        Button(L("profile.reset"), role: .destructive) { confirmsReset = true }
                            .frame(maxWidth: .infinity)
                    }
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

    private func studySection(_ profile: Profile) -> some View {
        Section(L("profile.study")) {
            NavigationLink {
                GroupEditor(profile: profile)
            } label: {
                LabeledContent(L("profile.group"), value: profile.group)
            }
            NavigationLink {
                SubgroupEditor(profile: profile)
            } label: {
                LabeledContent(L("profile.subgroup"), value: subgroupName(profile.subgroup))
            }
        }
    }

    private var dataSection: some View {
        Section(L("profile.data")) {
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

/// The user card at the top of the profile: initials, name, group and subgroup.
private struct ProfileCard: View {
    let profile: Profile
    @ScaledMetric(relativeTo: .title) private var avatarSize = 64

    private var initials: String {
        let words = profile.fullName.split(separator: " ")
        // "Фамилия Имя Отчество" → "ИФ"; a single word → its first letter.
        let letters = words.count > 1 ? [words[1], words[0]] : Array(words.prefix(1))
        return letters.compactMap(\.first).map(String.init).joined().uppercased()
    }

    var body: some View {
        HStack(spacing: 16) {
            Text(initials)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: avatarSize, height: avatarSize)
                .background(Circle().fill(Color.accentColor.gradient))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.fullName)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(profile.group) · \(L("course.label \(profile.course)"))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if profile.subgroup != .unspecified {
                    SubgroupBadge(subgroup: profile.subgroup.rawValue)
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityHint(L("profile.editNameHint"))
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

/// Picks another group from the server list.
private struct GroupEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let profile: Profile
    @State private var list = GroupList()
    @State private var selection: String?

    var body: some View {
        Group {
            switch list.state {
            case .loading:
                ProgressView()
            case .failed(let error):
                ErrorStateView(error: error) { await list.load(client: model.client) }
            case .loaded:
                GroupPickerView(groups: list.groups, selection: $selection)
            }
        }
        .navigationTitle(L("profile.group"))
        .task { await list.load(client: model.client) }
        .onAppear { selection = profile.group }
        .onChange(of: selection) {
            guard let selection, selection != profile.group,
                  let info = list.groups.first(where: { $0.name == selection }) else { return }
            var updated = profile
            updated.group = info.name
            updated.course = info.course
            model.save(profile: updated)
            dismiss()
        }
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
