import SwiftUI

enum HandOverlayRenderer {
    static func drawCropBoxes(
        _ cropBoxes: [HandCropBox],
        context: inout GraphicsContext,
        imageWidth: Double,
        imageHeight: Double,
        rect: CGRect
    ) {
        for cropBox in cropBoxes {
            let viewRect = viewRectForCropBox(
                cropBox,
                imageWidth: imageWidth,
                imageHeight: imageHeight,
                rect: rect
            )
            var path = Path()
            path.addRect(viewRect)
            let color: Color = cropBox.side == .left ? .orange : .purple
            context.stroke(path, with: .color(color.opacity(0.8)), lineWidth: 2.0)
        }
    }

    static func drawHands(
        _ hands: [HandLandmarkResult],
        context: inout GraphicsContext,
        imageWidth: Double,
        imageHeight: Double,
        rect: CGRect
    ) {
        for hand in hands {
            drawHand(
                hand,
                context: &context,
                imageWidth: imageWidth,
                imageHeight: imageHeight,
                rect: rect
            )
        }
    }

    private static func drawHand(
        _ hand: HandLandmarkResult,
        context: inout GraphicsContext,
        imageWidth: Double,
        imageHeight: Double,
        rect: CGRect
    ) {
        let points = hand.frameLandmarks.map {
            viewPoint($0, imageWidth: imageWidth, imageHeight: imageHeight, rect: rect)
        }
        guard points.count == 21 else { return }

        let lineColor: Color = hand.side == .left ? .cyan : .pink
        for edge in HandSkeletonTopology.connections {
            var path = Path()
            path.move(to: points[edge.0])
            path.addLine(to: points[edge.1])
            context.stroke(path, with: .color(lineColor), lineWidth: 3.0)
        }

        for (index, point) in points.enumerated() {
            let radius = index == 0 ? 5.0 : 3.5
            let circle = CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2.0,
                height: radius * 2.0
            )
            context.fill(Path(ellipseIn: circle), with: .color(.white))
            context.stroke(Path(ellipseIn: circle), with: .color(lineColor), lineWidth: 1.5)
        }
    }

    private static func viewPoint(
        _ landmark: HandLandmarkPoint,
        imageWidth: Double,
        imageHeight: Double,
        rect: CGRect
    ) -> CGPoint {
        CGPoint(
            x: rect.minX + CGFloat(landmark.x / imageWidth) * rect.width,
            y: rect.minY + CGFloat(landmark.y / imageHeight) * rect.height
        )
    }

    private static func viewRectForCropBox(
        _ cropBox: HandCropBox,
        imageWidth: Double,
        imageHeight: Double,
        rect: CGRect
    ) -> CGRect {
        CGRect(
            x: rect.minX + cropBox.rect.minX / CGFloat(imageWidth) * rect.width,
            y: rect.minY + cropBox.rect.minY / CGFloat(imageHeight) * rect.height,
            width: cropBox.rect.width / CGFloat(imageWidth) * rect.width,
            height: cropBox.rect.height / CGFloat(imageHeight) * rect.height
        )
    }
}
