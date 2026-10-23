import SwiftUI
import SkedCore

/// A Liquid Glass card.
struct GlassCard<Content: View>: View {
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(tint.map { .regular.tint($0.opacity(0.25)) } ?? .regular, in: .rect(cornerRadius: 24))
    }
}

/// Soft backdrop so glass has something to refract in both themes.
struct ScreenBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.18), Color(.systemBackground), Color.teal.opacity(0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

/// "Показаны данные от …" when the network failed and the cache is shown.
struct StaleDataBanner: View {
    let fetchedAt: Date?
    let reason: APIError
    var retry: () async -> Void

    var body: some View {
        GlassCard(tint: .orange) {
            // The button sits in the text column so it lines up with the
            // text, not with the icon.
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let fetchedAt {
                            Text(L("stale.title \(Format.dateTime(fetchedAt))"))
                                .font(.subheadline.weight(.semibold))
                        }
                        Text(reason.errorDescription ?? "")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button(L("action.retry")) {
                        Task { await retry() }
                    }
                    .buttonStyle(.glass)
                    .font(.footnote)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Full-screen error when there is nothing cached to show.
struct ErrorStateView: View {
    let error: APIError
    var retry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label(error.errorDescription ?? "", systemImage: "exclamationmark.icloud")
        } description: {
            Text(error.recoverySuggestion ?? "")
        } actions: {
            Button(L("action.retry")) {
                Task { await retry() }
            }
            .buttonStyle(.glassProminent)
            .accessibilityIdentifier("retry")
        }
    }
}

struct SubgroupBadge: View {
    let subgroup: Int

    var body: some View {
        Text(L("subgroup.badge \(subgroup)"))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .glassEffect(.regular.tint(subgroup == 1 ? .blue.opacity(0.3) : .purple.opacity(0.3)), in: .capsule)
    }
}

/// One lesson in the day list.
struct LessonRow: View {
    let lesson: Lesson

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            PairNumber(label: lesson.pairLabel)

            VStack(alignment: .leading, spacing: 4) {
                Text(lesson.subject)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Format.timeRange(lesson))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(Format.place(lesson))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let note = lesson.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Format.accessibilityLabel(lesson))
    }
}

/// The pair number in a glass circle, centred against the row.
struct PairNumber: View {
    let label: String
    var font: Font = .title3.weight(.bold).monospacedDigit()
    @ScaledMetric private var size: CGFloat

    init(label: String, compact: Bool = false) {
        self.label = label
        if compact {
            font = .subheadline.weight(.bold).monospacedDigit()
            _size = ScaledMetric(wrappedValue: 32, relativeTo: .subheadline)
        } else {
            _size = ScaledMetric(wrappedValue: 44, relativeTo: .title3)
        }
    }

    var body: some View {
        Text(label)
            .font(font)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(minWidth: size, minHeight: size)
            .padding(.horizontal, label.count > 2 ? 6 : 0)
            .glassEffect(.regular.tint(Color.accentColor.opacity(0.2)), in: .capsule)
            .accessibilityHidden(true)
    }
}

/// Compact row for the week view: numbered circle, then subject, time
/// range and place.
struct CompactLessonRow: View {
    let lesson: Lesson

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PairNumber(label: lesson.pairLabel, compact: true)

            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.subject)
                    .font(.subheadline.weight(.semibold))
                Text(Format.timeRange(lesson))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(Format.place(lesson))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Format.accessibilityLabel(lesson))
    }
}

/// "Занятия начинаются с …" and lunch breaks shown under a day's header.
struct DayNotes: View {
    let startsAt: String?
    let lunches: [Note]
    var font: Font = .subheadline

    var body: some View {
        if startsAt != nil || !lunches.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if let startsAt {
                    Label(L("home.startsAt \(startsAt)"), systemImage: "alarm")
                }
                ForEach(lunches, id: \.text) { lunch in
                    Label(Format.lunch(lunch), systemImage: "fork.knife")
                }
            }
            .font(font)
            .foregroundStyle(.secondary)
        }
    }
}
