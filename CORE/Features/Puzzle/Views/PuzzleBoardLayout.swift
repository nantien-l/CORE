import SwiftUI

struct PuzzleBoardLayout: Layout {
    let wide: Bool
    let expanded: Bool
    let boardHeight: CGFloat
    let spacing: CGFloat

    private let sidebarGap: CGFloat = 30

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        if expanded {
            return CGSize(width: width, height: boardHeight)
        }
        let panelWidth = wide ? sidebarWidth(for: width) : width
        let panelHeight = panelSizes(in: subviews, width: panelWidth).reduce(0) { $0 + $1.height } + spacing * 2
        let height = wide ? max(panelHeight, boardHeight) : panelHeight + spacing + boardHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if expanded {
            subviews[3].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
            return
        }

        let panelWidth = wide ? sidebarWidth(for: bounds.width) : bounds.width
        let sizes = panelSizes(in: subviews, width: panelWidth)
        let panelHeight = sizes.reduce(0) { $0 + $1.height } + spacing * 2
        // Keep the sidebar anchored when its controls change from play to results.
        var y = bounds.minY + (wide ? min(44, max(0, (bounds.height - panelHeight) / 2)) : 0)

        for index in 0..<3 {
            if index == 2 && !wide { y += boardHeight + spacing }
            subviews[index].place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: ProposedViewSize(sizes[index]))
            y += sizes[index].height + spacing
        }

        let boardOrigin = CGPoint(x: wide ? bounds.minX + panelWidth + sidebarGap : bounds.minX,
                                  y: wide ? bounds.midY - boardHeight / 2 : bounds.minY + sizes[0].height + sizes[1].height + spacing * 2)
        let boardWidth = wide ? max(0, bounds.width - panelWidth - sidebarGap) : bounds.width
        subviews[3].place(at: boardOrigin, anchor: .topLeading, proposal: ProposedViewSize(width: boardWidth, height: boardHeight))
    }

    private func sidebarWidth(for width: CGFloat) -> CGFloat {
        min(268, max(218, width * 0.235))
    }

    private func panelSizes(in subviews: Subviews, width: CGFloat) -> [CGSize] {
        (0..<3).map { index in
            let height = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            return CGSize(width: width, height: height)
        }
    }
}
