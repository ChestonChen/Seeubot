import SwiftUI

// 系统 API 速览：
// - Layout：SwiftUI 自定义布局协议，需要实现 sizeThatFits 和 placeSubviews。
// - ProposedViewSize：父容器给出的建议尺寸。
// - LayoutSubviews：SwiftUI 传进来的子视图集合。
// - sizeThatFits：询问布局需要多大空间。
// - placeSubviews：真正把每个子视图放到具体坐标。
// - CGPoint / CGSize / CGRect：系统几何类型，用来计算 chip 的位置和尺寸。
/// A simple left-aligned wrapping layout (chips flow onto new lines as needed).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows = layout(subviews: subviews, maxWidth: maxWidth)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        let width = rows.map { $0.maxX }.max() ?? 0
        rows.removeAll()
        // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout Void) {
        let rows = layout(subviews: subviews, maxWidth: bounds.width)
        for item in rows {
            subviews[item.index].place(
                at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + item.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(item.size))
        }
    }

    private struct Item { var index: Int; var x: CGFloat; var y: CGFloat; var size: CGSize
        var height: CGFloat { size.height }
        var maxX: CGFloat { x + size.width }
    }

    private func layout(subviews: LayoutSubviews, maxWidth: CGFloat) -> [Item] {
        var items: [Item] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for (i, sub) in subviews.enumerated() {
            let ideal = sub.sizeThatFits(.unspecified)
            // Clamp to the available width so an over-long item truncates instead of
            // overflowing and getting hard-clipped by the card.
            // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
            let sz = CGSize(width: min(ideal.width, maxWidth.isFinite ? maxWidth : ideal.width),
                            height: ideal.height)
            if x > 0, x + sz.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            items.append(Item(index: i, x: x, y: y, size: sz))
            x += sz.width + spacing
            // 系统 API（行级）：Swift 标准数学函数，用来计算动画曲线或边界值。
            rowHeight = max(rowHeight, sz.height)
        }
        return items
    }
}
