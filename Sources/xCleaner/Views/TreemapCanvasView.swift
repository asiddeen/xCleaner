import SwiftUI
import XCleanerCore

struct TreemapCanvasView: View {
    let nodes: [DiskNode]
    let selectedNodeID: String?
    let onSelectNode: (DiskNode) -> Void
    let onDrillDownNode: (DiskNode) -> Void

    @State private var hoveredRectID: String?

    var body: some View {
        GeometryReader { geo in
            let canvasBounds = CGRect(origin: .zero, size: geo.size)
            let rects = TreemapLayoutEngine.layout(nodes: nodes, in: canvasBounds)

            ZStack(alignment: .bottomLeading) {
                Canvas { context, _ in
                    for rect in rects {
                        let insetFrame = rect.frame.insetBy(dx: 1.5, dy: 1.5)
                        guard insetFrame.width > 1, insetFrame.height > 1 else { continue }

                        let path = Path(roundedRect: insetFrame, cornerRadius: 5)
                        let baseColor = tileColor(for: rect)
                        let isSelected = (rect.id == selectedNodeID)
                        let isHovered = (rect.id == hoveredRectID)

                        let fillOpacity: Double = isSelected ? 0.36 : (isHovered ? 0.28 : 0.19)
                        context.fill(path, with: .color(baseColor.opacity(fillOpacity)))

                        let strokeColor: Color = isSelected
                            ? Color.accentColor
                            : (isHovered ? baseColor.opacity(0.85) : baseColor.opacity(0.42))
                        context.stroke(path, with: .color(strokeColor), lineWidth: isSelected ? 2.0 : 1.0)

                        // Render crisp labels inside tiles large enough to stay legible
                        if insetFrame.width >= 58 && insetFrame.height >= 30 {
                            var subCtx = context
                            subCtx.clip(to: Path(insetFrame.insetBy(dx: 5, dy: 4)))

                            let titleText = Text(rect.title)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(Color.primary)
                            subCtx.draw(
                                titleText,
                                at: CGPoint(x: insetFrame.minX + 7, y: insetFrame.minY + 6),
                                anchor: .topLeading
                            )

                            if insetFrame.height >= 46 {
                                let sizeText = Text(ByteFormatting.string(from: rect.allocatedBytes))
                                    .font(.system(size: 10.5, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(Color.secondary)
                                subCtx.draw(
                                    sizeText,
                                    at: CGPoint(x: insetFrame.minX + 7, y: insetFrame.minY + 22),
                                    anchor: .topLeading
                                )
                            }
                        }
                    }
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hoveredRectID = rects.first(where: { $0.frame.contains(location) })?.id
                    case .ended:
                        hoveredRectID = nil
                    }
                }
                .gesture(
                    SpatialTapGesture(count: 2)
                        .onEnded { event in
                            if let hit = rects.first(where: { $0.frame.contains(event.location) }),
                               let node = hit.node, node.isDirectory {
                                onDrillDownNode(node)
                            }
                        }
                        .exclusively(before:
                            SpatialTapGesture(count: 1)
                                .onEnded { event in
                                    if let hit = rects.first(where: { $0.frame.contains(event.location) }),
                                       let node = hit.node {
                                        onSelectNode(node)
                                    }
                                }
                        )
                )

                // Hover HUD pill at bottom-left
                if let hoveredID = hoveredRectID,
                   let hovered = rects.first(where: { $0.id == hoveredID }) {
                    HStack(spacing: 6) {
                        Image(systemName: hovered.isDirectory ? "folder.fill" : "doc.fill")
                            .font(.system(size: 11))
                        Text(hovered.title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(ByteFormatting.string(from: hovered.allocatedBytes))
                            .font(.system(size: 11.5, weight: .bold))
                            .monospacedDigit()
                        if hovered.isDirectory {
                            Text("(Double-click to open)")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .padding(8)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private func tileColor(for rect: TreemapRect) -> Color {
        if let node = rect.node {
            if node.advisory.isPinnedByUser {
                return .blue
            }
            switch node.advisory.level {
            case .safe:
                return Color(nsColor: .systemGreen)
            case .caution:
                return rect.isDirectory ? Color.accentColor : Color(nsColor: .systemTeal)
            case .warning:
                return Color(nsColor: .systemOrange)
            case .protected:
                return .secondary
            }
        }
        return .secondary
    }
}
