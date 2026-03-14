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

    /// Fit workspace bounds to encompass given column frames with padding
    func fitToColumns(columnFrames: [UUID: CGRect]) {
        let cols = columns
        guard !cols.isEmpty else { return }

        let frames = cols.compactMap { columnFrames[$0.id] }
        guard frames.count == cols.count else {
            // Fallback: estimate from positions
            let pad = Workspace.padding
            let minX = cols.map { $0.positionX }.min()! - pad
            let maxX = cols.map { $0.positionX + 320 }.max()! + pad
            let minY = cols.map { $0.positionY + 200 - 150 }.min()! - pad - 28
            let maxY = cols.map { $0.positionY + 200 + 150 }.max()! + pad
            positionX = minX
            positionY = minY
            width = max(maxX - minX, Workspace.minWidth)
            height = max(maxY - minY, Workspace.minHeight)
            return
        }

        let pad = Workspace.padding
        let titleSpace: Double = 28
        let minX = frames.map { $0.minX }.min()! - pad
        let maxX = frames.map { $0.maxX }.max()! + pad
        let minY = frames.map { $0.minY }.min()! - pad - titleSpace
        let maxY = frames.map { $0.maxY }.max()! + pad
        positionX = minX
        positionY = minY
        width = max(maxX - minX, Workspace.minWidth)
        height = max(maxY - minY, Workspace.minHeight)
    }
}
