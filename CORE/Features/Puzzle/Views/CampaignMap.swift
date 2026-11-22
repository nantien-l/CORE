import SwiftUI

struct CampaignMap: View {
    let levels: [Level]
    let current: Int
    let cleared: Int
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    private let cyan = Color(red: 0.50, green: 0.91, blue: 1)
    private let sectors = ["First Descent", "Red Horizon", "Ember Circuit", "Obsidian Reach", "Fault Zone", "Switchback Depths"]

    private var unlocked: Int { min(cleared + 1, levels.count) }

    var body: some View {
        GeometryReader { canvas in
            let count = canvas.size.width >= 640 ? 10 : 5
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
            VStack(spacing: 0) {
                header
                Divider().overlay(cyan.opacity(0.15))
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 15) {
                            sectorCards(columns: columns)
                            unknownSignal
                        }
                        .frame(maxWidth: 790)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                    }
                    .task {
                        await Task.yield()
                        proxy.scrollTo((current - 1) / 10, anchor: .top)
                    }
                }
            }
        }
        .background {
            RadialGradient(colors: [Color(red: 0.08, green: 0.15, blue: 0.18), PuzzlePalette.background],
                           center: .topLeading, startRadius: 0, endRadius: 620).ignoresSafeArea()
        }
        .foregroundStyle(PuzzlePalette.stone)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "map")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(cyan)
                    .frame(width: 46, height: 46)
                    .background(cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(cyan.opacity(0.28)) }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Campaign map")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Level \(current) / \(levels.count)  ·  \(cleared) cleared")
                        .font(.system(.caption, design: .monospaced, weight: .medium))
                        .foregroundStyle(cyan)
                }
                Spacer(minLength: 4)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close map")
            }

            HStack(spacing: 5) {
                ForEach(sectors.indices, id: \.self) { index in
                    let fraction = min(1, max(0, Double(cleared - index * 10) / 10))
                    GeometryReader { segment in
                        Capsule()
                            .fill(cyan.opacity(0.12))
                            .overlay(alignment: .leading) {
                                Capsule().fill(cyan).frame(width: segment.size.width * fraction)
                            }
                    }
                    .frame(height: 4)
                }
            }
            .accessibilityHidden(true)
            HStack(spacing: 14) {
                Label("Current", systemImage: "scope").foregroundStyle(cyan)
                Label("Cleared", systemImage: "checkmark").foregroundStyle(PuzzlePalette.accent)
                Label("Locked", systemImage: "lock.fill").foregroundStyle(PuzzlePalette.muted)
            }
            .font(.caption2.weight(.medium))
            .accessibilityHidden(true)
        }
        .frame(maxWidth: 790)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    private func sectorCards(columns: [GridItem]) -> some View {
        ForEach(sectors.indices, id: \.self) { index in
            let sectorLevels = Array(levels.dropFirst(index * 10).prefix(10))
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%02d", index + 1))
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .foregroundStyle(cyan)
                    Text(sectors[index])
                        .font(.subheadline.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text("\(sectorLevels.filter { $0.id <= cleared }.count) / \(sectorLevels.count)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(PuzzlePalette.muted)
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(sectorLevels) { level in node(level) }
                }
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color(red: 0.058, green: 0.088, blue: 0.105))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15)
                            .strokeBorder(cyan.opacity((current - 1) / 10 == index ? 0.46 : 0.15))
                    }
            }
            .id(index)
        }
    }

    private var unknownSignal: some View {
        HStack(spacing: 13) {
            Image(systemName: "questionmark")
                .font(.system(.title2, design: .monospaced, weight: .bold))
                .frame(width: 47, height: 47)
                .background(cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(cyan.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                .shadow(color: cyan.opacity(0.25), radius: 7)
                .accessibilityHidden(true)

            Text("Unknown signal")
                .font(.system(.subheadline, design: .monospaced, weight: .semibold))

            Spacer(minLength: 0)
        }
        .foregroundStyle(cyan)
        .padding(12)
        .background(cyan.opacity(0.045), in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .strokeBorder(cyan.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        }
        .accessibilityElement(children: .combine)
    }

    private func node(_ level: Level) -> some View {
        let selected = level.id == current
        let finished = level.id <= cleared
        let locked = level.id > unlocked
        let tint = selected ? cyan : (finished ? PuzzlePalette.accent : PuzzlePalette.muted)
        let symbol = selected ? "scope" : (finished ? "checkmark" : (locked ? "lock.fill" : "circle.dotted"))
        return Button {
            onSelect(level.id - 1)
            dismiss()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(String(format: "%02d", level.id))
                    .font(.system(.subheadline, design: .monospaced, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 53)
            .foregroundStyle(tint)
            .background(tint.opacity(selected ? 0.19 : 0.06), in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(selected ? 0.83 : 0.18)) }
            .overlay(alignment: .topTrailing) {
                if selected && finished {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(PuzzlePalette.accent)
                        .padding(5)
                }
            }
            .shadow(color: selected ? cyan.opacity(0.23) : .clear, radius: 7)
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .accessibilityLabel("Level \(level.id), \(level.name)")
        .accessibilityValue(selected ? (finished ? "Current level, cleared" : "Current level") : (finished ? "Cleared" : (locked ? "Locked" : "Available")))
    }
}
