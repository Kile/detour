import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \QuestRecord.completedAt, order: .reverse) private var records: [QuestRecord]
    @Query private var profiles: [PlayerProfile]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    BadgeGrid(earned: profiles.first?.badges ?? [])
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                } header: {
                    Text("Badges")
                } footer: {
                    if let profile = profiles.first {
                        Text("\(records.count) quest\(records.count == 1 ? "" : "s") · \(profile.xp) XP · best streak \(profile.bestStreak) day\(profile.bestStreak == 1 ? "" : "s") · \(profile.rerolls) rerolls")
                    }
                }

                Section("Completed quests") {
                    if records.isEmpty {
                        ContentUnavailableView {
                            Label { Text("No quests yet") } icon: { DetourMark(color: .secondary).frame(width: 44, height: 44) }
                        } description: {
                            Text("Tap “Give me a quest” and your detours will appear here.")
                        }
                    }
                    ForEach(records) { record in
                        HistoryRow(record: record)
                    }
                }
            }
            .navigationTitle("Journal")
        }
    }
}

private struct HistoryRow: View {
    var record: QuestRecord

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let data = record.thumbnail, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").font(.title2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.quaternary)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(record.title).font(.headline).lineLimit(1)
                Text(record.feedback).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 6) {
                    Image(systemName: record.scope.symbol)
                    Text(record.completedAt, format: .dateTime.day().month().hour().minute())
                    if let theme = record.theme { Text(theme.emoji) }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text("+\(record.pointsAwarded)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(Theme.gold)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct BadgeGrid: View {
    var earned: Set<Badge>

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 14) {
            ForEach(Badge.allCases) { badge in
                let has = earned.contains(badge)
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(has ? AnyShapeStyle(Theme.questGradient) : AnyShapeStyle(.quaternary))
                            .frame(width: 52, height: 52)
                        Image(systemName: badge.symbol)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(has ? Theme.markOnPrimary : .secondary)
                    }
                    Text(badge.title)
                        .font(.caption2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .foregroundStyle(has ? .primary : .secondary)
                }
                .opacity(has ? 1 : 0.55)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(badge.title): \(badge.detail). \(has ? "Earned" : "Not earned yet")")
            }
        }
    }
}
