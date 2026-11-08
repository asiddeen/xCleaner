import CoreGraphics
import Foundation

public struct TreemapRect: Identifiable, Sendable, Equatable {
    public let id: String
    public let frame: CGRect
    public let title: String
    public let allocatedBytes: Int64
    public let fraction: Double
    public let isDirectory: Bool
    public let advisoryLevel: AdvisoryLevel
    public let node: DiskNode?

    public init(
        id: String,
        frame: CGRect,
        title: String,
        allocatedBytes: Int64,
        fraction: Double,
        isDirectory: Bool,
        advisoryLevel: AdvisoryLevel,
        node: DiskNode?
    ) {
        self.id = id
        self.frame = frame
        self.title = title
        self.allocatedBytes = allocatedBytes
        self.fraction = fraction
        self.isDirectory = isDirectory
        self.advisoryLevel = advisoryLevel
        self.node = node
    }
}

public enum TreemapLayoutEngine {
    private struct WeightedItem {
        let id: String
        let title: String
        let bytes: Int64
        let fraction: Double
        let isDirectory: Bool
        let advisoryLevel: AdvisoryLevel
        let node: DiskNode?
        let normalizedArea: CGFloat
    }

    public static func layout(
        nodes: [DiskNode],
        in bounds: CGRect,
        minimumSliceRatio: Double = 0.0075
    ) -> [TreemapRect] {
        guard bounds.width > 1, bounds.height > 1 else { return [] }
        let positiveNodes = nodes
            .filter { $0.allocatedBytes > 0 }
            .sorted { $0.allocatedBytes > $1.allocatedBytes }

        let totalBytes = positiveNodes.reduce(Int64(0)) { $0 + $1.allocatedBytes }
        guard totalBytes > 0 else { return [] }

        // Separate primary visible items from tiny tail items (< minimumSliceRatio)
        var primaryNodes: [DiskNode] = []
        var tailNodes: [DiskNode] = []

        for node in positiveNodes {
            let ratio = Double(node.allocatedBytes) / Double(totalBytes)
            if ratio >= minimumSliceRatio || primaryNodes.isEmpty {
                primaryNodes.append(node)
            } else {
                tailNodes.append(node)
            }
        }

        // Only aggregate if there are 2+ tail items; if just 1, show it directly
        if tailNodes.count == 1, let single = tailNodes.first {
            primaryNodes.append(single)
            tailNodes.removeAll()
        }

        let totalCanvasArea = bounds.width * bounds.height
        var weightedItems: [WeightedItem] = primaryNodes.map { node in
            let frac = Double(node.allocatedBytes) / Double(totalBytes)
            return WeightedItem(
                id: node.id,
                title: node.name,
                bytes: node.allocatedBytes,
                fraction: frac,
                isDirectory: node.isDirectory,
                advisoryLevel: node.advisory.level,
                node: node,
                normalizedArea: totalCanvasArea * CGFloat(frac)
            )
        }

        if !tailNodes.isEmpty {
            let tailBytes = tailNodes.reduce(Int64(0)) { $0 + $1.allocatedBytes }
            let frac = Double(tailBytes) / Double(totalBytes)
            if tailBytes > 0 {
                weightedItems.append(
                    WeightedItem(
                        id: "__other_smaller_items__",
                        title: "Other (\(tailNodes.count) items)",
                        bytes: tailBytes,
                        fraction: frac,
                        isDirectory: false,
                        advisoryLevel: .caution,
                        node: nil,
                        normalizedArea: totalCanvasArea * CGFloat(frac)
                    )
                )
            }
        }

        // Re-sort descending so squarify invariant holds even if aggregated tail bucket exceeds smallest primary
        weightedItems.sort { $0.normalizedArea > $1.normalizedArea }

        var output: [TreemapRect] = []
        squarify(
            items: weightedItems,
            currentRow: [],
            remainingRect: bounds,
            output: &output
        )
        return output
    }

    private static func squarify(
        items: [WeightedItem],
        currentRow: [WeightedItem],
        remainingRect: CGRect,
        output: inout [TreemapRect]
    ) {
        guard remainingRect.width > 0.0001, remainingRect.height > 0.0001 else {
            return
        }

        if items.isEmpty {
            if !currentRow.isEmpty {
                _ = layoutRow(currentRow, in: remainingRect, output: &output)
            }
            return
        }

        let nextItem = items[0]
        let rest = Array(items.dropFirst())
        let shortSide = min(remainingRect.width, remainingRect.height)

        if currentRow.isEmpty {
            squarify(
                items: rest,
                currentRow: [nextItem],
                remainingRect: remainingRect,
                output: &output
            )
            return
        }

        let currentWorst = worstAspectRatio(row: currentRow, sideLength: shortSide)
        let candidateRow = currentRow + [nextItem]
        let candidateWorst = worstAspectRatio(row: candidateRow, sideLength: shortSide)

        if candidateWorst <= currentWorst {
            squarify(
                items: rest,
                currentRow: candidateRow,
                remainingRect: remainingRect,
                output: &output
            )
        } else {
            let leftoverRect = layoutRow(currentRow, in: remainingRect, output: &output)
            squarify(
                items: items,
                currentRow: [],
                remainingRect: leftoverRect,
                output: &output
            )
        }
    }

    private static func worstAspectRatio(row: [WeightedItem], sideLength: CGFloat) -> CGFloat {
        guard !row.isEmpty, sideLength > 0 else { return .greatestFiniteMagnitude }
        let areas = row.map(\.normalizedArea)
        let sum = areas.reduce(0, +)
        guard sum > 0, let maxArea = areas.max(), let minArea = areas.min(), minArea > 0 else {
            return .greatestFiniteMagnitude
        }
        let s2 = sideLength * sideLength
        let sum2 = sum * sum
        return max((s2 * maxArea) / sum2, sum2 / (s2 * minArea))
    }

    private static func layoutRow(
        _ row: [WeightedItem],
        in rect: CGRect,
        output: inout [TreemapRect]
    ) -> CGRect {
        let rowArea = row.reduce(CGFloat(0)) { $0 + $1.normalizedArea }
        guard rowArea > 0, rect.width > 0, rect.height > 0 else { return .zero }

        let layoutHorizontally = rect.width >= rect.height
        if layoutHorizontally {
            // Slice a vertical strip of width = rowArea / rect.height on the left side of rect
            let stripWidth = min(rect.width, rowArea / rect.height)
            var cursorY = rect.minY
            for (index, item) in row.enumerated() {
                let itemHeight: CGFloat
                if index == row.count - 1 {
                    itemHeight = max(0, rect.maxY - cursorY)
                } else {
                    itemHeight = min(rect.maxY - cursorY, stripWidth > 0 ? (item.normalizedArea / stripWidth) : 0)
                }
                let frame = CGRect(x: rect.minX, y: cursorY, width: stripWidth, height: itemHeight)
                appendRect(item: item, frame: frame, output: &output)
                cursorY += itemHeight
            }
            return CGRect(
                x: rect.minX + stripWidth,
                y: rect.minY,
                width: max(0, rect.width - stripWidth),
                height: rect.height
            )
        } else {
            // Slice a horizontal strip of height = rowArea / rect.width at the top of rect
            let stripHeight = min(rect.height, rowArea / rect.width)
            var cursorX = rect.minX
            for (index, item) in row.enumerated() {
                let itemWidth: CGFloat
                if index == row.count - 1 {
                    itemWidth = max(0, rect.maxX - cursorX)
                } else {
                    itemWidth = min(rect.maxX - cursorX, stripHeight > 0 ? (item.normalizedArea / stripHeight) : 0)
                }
                let frame = CGRect(x: cursorX, y: rect.minY, width: itemWidth, height: stripHeight)
                appendRect(item: item, frame: frame, output: &output)
                cursorX += itemWidth
            }
            return CGRect(
                x: rect.minX,
                y: rect.minY + stripHeight,
                width: rect.width,
                height: max(0, rect.height - stripHeight)
            )
        }
    }

    private static func appendRect(item: WeightedItem, frame: CGRect, output: inout [TreemapRect]) {
        guard frame.width > 0, frame.height > 0 else { return }
        output.append(
            TreemapRect(
                id: item.id,
                frame: frame,
                title: item.title,
                allocatedBytes: item.bytes,
                fraction: item.fraction,
                isDirectory: item.isDirectory,
                advisoryLevel: item.advisoryLevel,
                node: item.node
            )
        )
    }
}
