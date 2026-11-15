import SwiftUI

/// Quick picks: scope, venue line, theme, difficulty. Everything is remembered.
struct ScopeSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @FocusState private var venueFocused: Bool

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Where?") {
                        HStack(spacing: 10) {
                            ForEach(QuestScope.allCases) { scope in
                                ChoiceTile(title: scope.title, symbol: scope.symbol, selected: settings.scope == scope) {
                                    settings.scope = scope
                                    if scope == .venue { venueFocused = settings.venueDescription.isEmpty }
                                }
                            }
                        }
                        Text(settings.scope.blurb).font(.footnote).foregroundStyle(.secondary)
                    }

                    if settings.scope == .venue {
                        section("Your venue, in one line") {
                            TextField("e.g. HackLondon 2026 at Imperial College, South Kensington", text: $settings.venueDescription)
                                .focused($venueFocused)
                                .accessibilityIdentifier("venueField")
                                .submitLabel(.done)
                                .onSubmit { venueFocused = false }
                                .padding(12)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                                // The whole box focuses the field, not just the text line.
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                                .onTapGesture { venueFocused = true }
                            Text("I'll look it up once (layout, rooms, events, sponsors) and remember it.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }

                    section("Theme") {
                        FlowChips(items: [nil] + QuestTheme.allCases.map(Optional.some), selected: settings.theme) { theme in
                            theme.map { "\($0.emoji) \($0.title)" } ?? "🎲 Surprise me"
                        } onSelect: { settings.theme = $0 }
                    }

                    section("Difficulty") {
                        Picker("Difficulty", selection: $settings.difficulty) {
                            ForEach(DifficultyPreference.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        if settings.difficulty == .hard {
                            Text("Hard means hard: big counts, rare finds, several things in one shot.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }

                    section("People") {
                        Toggle(isOn: $settings.allowPeople) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("👥 Quests with other people")
                                Text("Chat, team up, find someone who… Faces are blurred on your phone before photos are checked.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("peopleToggle")
                    }
                }
                .padding(20)
            }
            .navigationTitle("Quest settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }
}

private struct ChoiceTile: View {
    var title: String
    var symbol: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title2)
                Text(title).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(selected ? Theme.onPrimary : .primary)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? AnyShapeStyle(Theme.questGradient) : AnyShapeStyle(.quaternary.opacity(0.5)))
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Wrapping row of selectable chips.
struct FlowChips<Item: Hashable>: View {
    var items: [Item]
    var selected: Item
    var label: (Item) -> String
    var onSelect: (Item) -> Void

    var body: some View {
        WrappingHStack(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { onSelect(item) } label: {
                    Text(label(item))
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(item == selected ? Theme.onPrimary : .primary)
                        .background {
                            Capsule().fill(item == selected ? AnyShapeStyle(Theme.questGradient) : AnyShapeStyle(.quaternary.opacity(0.5)))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(item == selected ? .isSelected : [])
            }
        }
    }
}

/// Minimal flow layout.
struct WrappingHStack: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
