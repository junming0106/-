import Foundation
import SwiftData
import CoreGraphics

@Model
final class Workspace {
    var id: UUID
    var name: String
    /// Top-left corner in canvas space
    var positionX: Double
    var positionY: Double
    var width: Double
    var height: Double
    var order: Int

    @Relationship(deleteRule: .nullify, inverse: \BoardColumn.workspace)
    var columns: [BoardColumn]

    var board: Board?

    static let defaultWidth: Double = 400
    static let defaultHeight: Double = 300
    static let padding: Double = 40
    static let minWidth: Double = 200
    static let minHeight: Double = 150

    init(
        name: String = "Workspace",
        positionX: Double = 0,
        positionY: Double = 0,
        width: Double = 400,
        height: Double = 300,
        order: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.positionX = positionX
        self.positionY = positionY
        self.width = width
        self.height = height
        self.order = order
        self.columns = []
    }

    /// Expand workspace bounds only on edges where columns exceed current bounds.
    /// Never shrinks — only grows the specific edge that overflows.
    func expandToFitColumns(columnFrames: [UUID: CGRect]) {
        let cols = columns
        guard !cols.isEmpty else { return }

        let pad = Workspace.padding
        let titleSpace: Double = 28

        let frames = cols.compactMap { columnFrames[$0.id] }
        let needsLeft: Double
        let needsRight: Double
        let needsTop: Double
        let needsBottom: Double

        if frames.count == cols.count {
            needsLeft = frames.map { $0.minX }.min()! - pad
            needsRight = frames.map { $0.maxX }.max()! + pad
            needsTop = frames.map { $0.minY }.min()! - pad - titleSpace
            needsBottom = frames.map { $0.maxY }.max()! + pad
        } else {
            // Fallback: estimate from stored positions
            needsLeft = cols.map { $0.positionX }.min()! - pad
            needsRight = cols.map { $0.positionX + 320 }.max()! + pad
            needsTop = cols.map { $0.positionY + 200 - 150 }.min()! - pad - titleSpace
            needsBottom = cols.map { $0.positionY + 200 + 150 }.max()! + pad
        }

        let currentRight = positionX + width
        let currentBottom = positionY + height

        // Expand left edge (moves origin left, increases width)
        if needsLeft < positionX {
            let diff = positionX - needsLeft
            positionX = needsLeft
            width += diff
        }

        // Expand right edge (increases width only)
        if needsRight > currentRight {
            width += needsRight - currentRight
        }

        // Expand top edge (moves origin up, increases height)
        if needsTop < positionY {
            let diff = positionY - needsTop
            positionY = needsTop
            height += diff
        }

        // Expand bottom edge (increases height only)
        if needsBottom > currentBottom {
            height += needsBottom - currentBottom
        }

        // Enforce minimums
        width = max(width, Workspace.minWidth)
        height = max(height, Workspace.minHeight)
    }

    /// Reset workspace bounds to exactly fit columns (shrinks and grows as needed)
    func fitToColumns(columnFrames: [UUID: CGRect]) {
        let cols = columns
        guard !cols.isEmpty else { return }

        let pad = Workspace.padding
        let titleSpace: Double = 28

        let frames = cols.compactMap { columnFrames[$0.id] }

        let left: Double
        let right: Double
        let top: Double
        let bottom: Double

        if frames.count == cols.count {
            left = frames.map { $0.minX }.min()! - pad
            right = frames.map { $0.maxX }.max()! + pad
            top = frames.map { $0.minY }.min()! - pad - titleSpace
            bottom = frames.map { $0.maxY }.max()! + pad
        } else {
            left = cols.map { $0.positionX }.min()! - pad
            right = cols.map { $0.positionX + 320 }.max()! + pad
            top = cols.map { $0.positionY + 200 - 150 }.min()! - pad - titleSpace
            bottom = cols.map { $0.positionY + 200 + 150 }.max()! + pad
        }

        positionX = left
        positionY = top
        width = max(right - left, Workspace.minWidth)
        height = max(bottom - top, Workspace.minHeight)
    }
}
