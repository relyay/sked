import SwiftUI
import VKSITCore

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
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    if let fetchedAt {
                        Text(L("stale.title \(Format.dateTime(fetchedAt))"))
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(reason.errorDescription ?? "")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundStyle(.orange)
            }
            Button(L("action.retry")) {
                Task { await retry() }
            }
            .buttonStyle(.glass)
            .font(.footnote)
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
                Text(Format.timeRange(lesson))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(lesson.subject)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Format.place(lesson))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let note = lesson.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let subgroup = lesson.subgroup {
                    SubgroupBadge(subgroup: subgroup)
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
    @ScaledMetric(relativeTo: .title3) private var size = 44

    var body: some View {
        Text(label)
            .font(.title3.weight(.bold).monospacedDigit())
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(minWidth: size, minHeight: size)
            .padding(.horizontal, label.count > 2 ? 6 : 0)
            .glassEffect(.regular.tint(Color.accentColor.opacity(0.2)), in: .capsule)
            .accessibilityHidden(true)
    }
}

/// Compact row for the week view: number and start time form a column
/// centred against the subject and place lines.
struct CompactLessonRow: View {
    let lesson: Lesson
    @ScaledMetric(relativeTo: .subheadline) private var columnWidth = 48

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(spacing: 2) {
                Text(lesson.pairLabel)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                Text(lesson.start)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: columnWidth)

            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.subject)
                    .font(.subheadline.weight(.semibold))
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
