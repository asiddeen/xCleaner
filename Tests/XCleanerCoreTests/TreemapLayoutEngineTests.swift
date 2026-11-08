import CoreGraphics
import Foundation
import Testing
@testable import XCleanerCore

@Suite("Squarified Treemap Layout Engine")
struct TreemapLayoutEngineTests {
    @Test("Produces bounded, non-degenerate rectangles conserving 100% of canvas area and aggregating tiny tail items")
    func laysOutValidRectanglesAndHandlesEdgeCases() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 500)
        #expect(TreemapLayoutEngine.layout(nodes: [], in: bounds).isEmpty)

        let dummyAdv = ItemAdvisory(
            level: .caution,
            badgeTitle: "Caution",
            whatIsThis: "Folder",
            consequenceIfRemoved: "Review"
        )

        var nodes: [DiskNode] = [
            DiskNode(url: URL(fileURLWithPath: "/tmp/a"), isDirectory: true, allocatedBytes: 50_000_000, logicalBytes: 50_000_000, itemCount: 10, advisory: dummyAdv),
            DiskNode(url: URL(fileURLWithPath: "/tmp/b"), isDirectory: true, allocatedBytes: 30_000_000, logicalBytes: 30_000_000, itemCount: 5, advisory: dummyAdv),
            DiskNode(url: URL(fileURLWithPath: "/tmp/c"), isDirectory: false, allocatedBytes: 19_000_000, logicalBytes: 19_000_000, itemCount: 1, advisory: dummyAdv)
        ]
        // Add 5 tiny tail items (< 0.75% each)
        for idx in 1...5 {
            nodes.append(
                DiskNode(
                    url: URL(fileURLWithPath: "/tmp/tiny-\(idx)"),
                    isDirectory: false,
                    allocatedBytes: 200_000,
                    logicalBytes: 200_000,
                    itemCount: 1,
                    advisory: dummyAdv
                )
            )
        }

        let rects = TreemapLayoutEngine.layout(nodes: nodes, in: bounds)
        #expect(rects.count == 4) // 3 primary + 1 aggregated "Other (5 items)"
        #expect(rects.contains { $0.id == "__other_smaller_items__" })

        var areaSum: CGFloat = 0
        for rect in rects {
            #expect(rect.frame.width > 0)
            #expect(rect.frame.height > 0)
            #expect(rect.frame.minX >= bounds.minX - 0.01)
            #expect(rect.frame.minY >= bounds.minY - 0.01)
            #expect(rect.frame.maxX <= bounds.maxX + 0.01)
            #expect(rect.frame.maxY <= bounds.maxY + 0.01)
            areaSum += rect.frame.width * rect.frame.height
        }

        let expectedArea = bounds.width * bounds.height
        #expect(abs(areaSum - expectedArea) < 1.0)
    }
}
