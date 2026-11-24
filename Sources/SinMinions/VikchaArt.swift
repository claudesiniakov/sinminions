import AppKit
import QuartzCore
import SinMinionsCore

extension CompanionCharacter {
    @MainActor
    func makeArt(style: GhostStyle, scale: CGFloat, coffee: Bool, outfit: Outfit) -> any CompanionArt {
        switch self {
        case .f: return GhostArt(style: style, scale: scale, coffee: coffee)
        case .ab: return GoldenArt(scale: scale, coffee: coffee, outfit: outfit)
        case .v: return VikchaArt(scale: scale, coffee: coffee)
        }
    }
}

@MainActor
final class VikchaArt: CompanionArt {
    let root = CALayer()
    let body = CAShapeLayer()
    let eyes = CALayer()
    let bodyPath: CGPath
    let eyesHome: CGPoint
    let glowScale: CGFloat = 0.65

    private let leftLeg = CALayer()
    private let rightLeg = CALayer()
    private let leftArm = CALayer()
    private let rightArm = CALayer()
    private let rightEye = CALayer()
    private let sparks = CAShapeLayer()

    // Координаты рисунка отсчитываются от верхнего левого угла рамки 48 × 56.
    private enum Segment {
        case move(CGFloat, CGFloat)
        case line(CGFloat, CGFloat)
        case quad(CGFloat, CGFloat, CGFloat, CGFloat)
        case curve(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
        case oval(CGFloat, CGFloat, CGFloat, CGFloat)
        case close
    }

    init(scale: CGFloat, coffee: Bool) {
        let size = CGSize(width: 48 * scale, height: 56 * scale)
        let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: 0, ty: size.height)
        let bounds = CGRect(origin: .zero, size: size)

        func path(for segments: [Segment]) -> CGPath {
            let path = CGMutablePath()
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
            for segment in segments {
                switch segment {
                case let .move(x, y):
                    path.move(to: point(x, y), transform: transform)
                case let .line(x, y):
                    path.addLine(to: point(x, y), transform: transform)
                case let .quad(cx, cy, x, y):
                    path.addQuadCurve(to: point(x, y), control: point(cx, cy), transform: transform)
                case let .curve(ax, ay, bx, by, x, y):
                    path.addCurve(to: point(x, y), control1: point(ax, ay), control2: point(bx, by), transform: transform)
                case let .oval(x, y, width, height):
                    path.addEllipse(in: CGRect(x: x, y: y, width: width, height: height), transform: transform)
                case .close:
                    path.closeSubpath()
                }
            }
            return path
        }

        bodyPath = path(for: [
            .move(8, 18), .curve(8, 7, 15, 2.5, 24, 2.8), .curve(34, 2.5, 40, 9, 40, 17),
            .curve(40, 25, 39, 29, 36, 34), .line(36, 42), .line(31, 43), .line(31, 48),
            .line(34, 51), .line(34, 53), .line(25, 53), .line(24, 45), .line(23, 53),
            .line(14, 53), .line(14, 51), .line(17, 48), .line(17, 43), .line(12, 42),
            .line(12, 34), .curve(9, 32, 7, 26, 8, 18), .close
        ])
        eyesHome = CGPoint(x: size.width / 2, y: (56 - 18.9) * scale)
        root.bounds = bounds
        eyes.bounds = bounds
        eyes.anchorPoint = CGPoint(x: 0.5, y: eyesHome.y / size.height)
        eyes.position = eyesHome

        func position(_ layer: CALayer, x: CGFloat, y: CGFloat) {
            layer.bounds = bounds
            layer.anchorPoint = CGPoint(x: x / 48, y: 1 - y / 56)
            layer.position = CGPoint(x: x * scale, y: (56 - y) * scale)
        }

        position(leftLeg, x: 20, y: 41)
        position(rightLeg, x: 28, y: 41)
        position(leftArm, x: 16.5, y: 31)
        position(rightArm, x: 31.5, y: 31)
        position(rightEye, x: 31, y: 19)

        body.frame = bounds
        body.path = bodyPath
        body.fillColor = .clear
        body.shadowPath = bodyPath
        body.shadowColor = CompanionView.Palette.rgb(0xe98dff).cgColor
        body.shadowOffset = .zero
        root.addSublayer(body)

        func paint(
            _ segments: [Segment],
            fill: UInt32? = nil,
            gradient: (CGFloat, CGFloat, CGFloat, CGFloat, [UInt32])? = nil,
            stroke: UInt32? = nil,
            width: CGFloat = 0,
            on parent: CALayer? = nil
        ) {
            let parent = parent ?? root
            let shapePath = path(for: segments)
            if let (x1, y1, x2, y2, colors) = gradient {
                let layer = CAGradientLayer()
                layer.frame = bounds
                layer.startPoint = CGPoint(x: x1 / 48, y: 1 - y1 / 56)
                layer.endPoint = CGPoint(x: x2 / 48, y: 1 - y2 / 56)
                layer.colors = colors.map { CompanionView.Palette.rgb($0).cgColor }
                let mask = CAShapeLayer()
                mask.frame = bounds
                mask.path = shapePath
                layer.mask = mask
                parent.addSublayer(layer)
            }
            if fill != nil || stroke != nil {
                let shape = CAShapeLayer()
                shape.frame = bounds
                shape.path = shapePath
                shape.fillColor = fill.map { CompanionView.Palette.rgb($0).cgColor }
                shape.strokeColor = stroke.map { CompanionView.Palette.rgb($0).cgColor }
                shape.lineWidth = width * scale
                shape.lineCap = .round
                shape.lineJoin = .round
                parent.addSublayer(shape)
            }
        }

        // Волосы за спиной.
        paint([
            .move(8, 18), .curve(8, 7, 15, 2.5, 24, 2.8), .curve(34, 2.5, 40, 9, 40, 17),
            .curve(40, 25, 39, 29, 36, 34), .curve(34, 31, 30, 33, 29, 31), .curve(26, 34, 20, 33, 18, 31),
            .curve(16, 33, 13, 35, 11, 34), .curve(11, 30, 7, 27, 8, 18), .close
        ], gradient: (15, 5, 33, 34, [0xa46be3, 0x693c9b, 0x3c255b]), stroke: 0x32204f, width: 1.25)
        paint([
            .move(10, 18), .curve(9, 25, 12, 31, 13, 32)
        ], stroke: 0xad76da, width: 0.55)
        paint([
            .move(37, 17), .curve(37, 24, 37, 29, 34, 31)
        ], stroke: 0xad76da, width: 0.55)
        paint([
            .move(35, 18), .curve(35, 25, 34, 29, 31, 31)
        ], stroke: 0x4c2c71, width: 0.55)

        // Ноги и ботинки.
        root.addSublayer(leftLeg)
        paint([
            .move(17.4, 40), .line(22.6, 40), .line(22.1, 46),
            .line(22.1, 48), .line(17.6, 48), .quad(17.3, 43, 17.4, 40),
            .close
        ], gradient: (15, 10, 27, 40, [0xfff1da, 0xffd1bc, 0xefa197]), stroke: 0x32204f, width: 0.8, on: leftLeg)
        paint([
            .move(17.7, 45), .line(22.2, 45), .line(22.2, 48),
            .line(17.7, 48), .close
        ], fill: 0xf4e9ff, stroke: 0x32204f, width: 0.6, on: leftLeg)
        paint([
            .move(17.6, 46), .line(22.3, 46)
        ], stroke: 0xb385cb, width: 0.45, on: leftLeg)
        paint([
            .move(17.3, 47), .line(22.7, 47), .line(22.8, 51),
            .curve(16.9, 51, 15.3, 51.3, 15.3, 52.3), .curve(22.6, 53, 18.7, 53, 17.6, 52.8), .quad(17.3, 51, 17.3, 47),
            .close
        ], gradient: (14, 47, 22, 53, [0x8057a2, 0x38264e, 0x271b3b]), stroke: 0x32204f, width: 0.8, on: leftLeg)
        paint([
            .move(17.8, 52), .quad(20, 52.6, 16.7, 52.5)
        ], stroke: 0xbc81c5, width: 0.46, on: leftLeg)
        paint([
            .move(18.6, 48.45), .line(21, 48.45)
        ], stroke: 0xf4caff, width: 0.4, on: leftLeg)
        paint([
            .move(18.6, 49.45), .line(21, 49.45)
        ], stroke: 0xf4caff, width: 0.4, on: leftLeg)
        root.addSublayer(rightLeg)
        paint([
            .move(25.4, 40), .line(30.6, 40), .line(30.1, 46),
            .line(30.1, 48), .line(25.6, 48), .quad(25.3, 43, 25.4, 40),
            .close
        ], gradient: (15, 10, 27, 40, [0xfff1da, 0xffd1bc, 0xefa197]), stroke: 0x32204f, width: 0.8, on: rightLeg)
        paint([
            .move(25.7, 45), .line(30.2, 45), .line(30.2, 48),
            .line(25.7, 48), .close
        ], fill: 0xf4e9ff, stroke: 0x32204f, width: 0.6, on: rightLeg)
        paint([
            .move(25.6, 46), .line(30.3, 46)
        ], stroke: 0xb385cb, width: 0.45, on: rightLeg)
        paint([
            .move(25.3, 47), .line(30.7, 47), .line(30.8, 51),
            .curve(31.1, 51, 32.7, 51.3, 32.7, 52.3), .curve(30.6, 53, 26.7, 53, 25.6, 52.8), .quad(25.3, 51, 25.3, 47),
            .close
        ], gradient: (14, 47, 22, 53, [0x8057a2, 0x38264e, 0x271b3b]), stroke: 0x32204f, width: 0.8, on: rightLeg)
        paint([
            .move(25.8, 52), .quad(28, 52.6, 31.3, 52.5)
        ], stroke: 0xbc81c5, width: 0.46, on: rightLeg)
        paint([
            .move(26.6, 48.45), .line(29, 48.45)
        ], stroke: 0xf4caff, width: 0.4, on: rightLeg)
        paint([
            .move(26.6, 49.45), .line(29, 49.45)
        ], stroke: 0xf4caff, width: 0.4, on: rightLeg)

        // Юбка.
        paint([
            .move(18.5, 35), .line(29.5, 35), .line(33.5, 42),
            .curve(31, 43.6, 27, 43.5, 24, 44), .curve(20, 43.5, 16, 44, 14.5, 42), .line(18.5, 35),
            .close
        ], gradient: (17, 36, 30, 44, [0x825eb0, 0x4a2d75, 0x6c4c91]), stroke: 0x32204f, width: 0.85)
        paint([
            .move(22, 37), .line(19, 43.1)
        ], stroke: 0xae83cc, width: 0.45)
        paint([
            .move(23, 38), .line(22, 43.3)
        ], stroke: 0x3d285a, width: 0.45)
        paint([
            .move(26, 37), .line(29, 43.1)
        ], stroke: 0xae83cc, width: 0.45)
        paint([
            .move(25, 38), .line(26, 43.3)
        ], stroke: 0x3d285a, width: 0.45)
        paint([
            .move(16.9, 41.4), .curve(20, 42.4, 24, 42.8, 26, 42.4), .curve(29, 42.5, 30.5, 42, 31.8, 41.6)
        ], stroke: 0xbb92d6, width: 0.38)

        // Рукава и жакет.
        root.addSublayer(leftArm)
        paint([
            .move(14.5, 30), .curve(16.5, 29, 18.5, 29.5, 18.7, 31), .line(12.7, 38.8),
            .line(13.6, 40.4), .line(16.9, 39.7), .quad(14.6, 34, 14.5, 30),
            .close
        ], gradient: (15, 29, 33, 40, [0xffb4d7, 0xe775a9, 0xa94382]), stroke: 0x32204f, width: 0.78, on: leftArm)
        paint([
            .move(16.7, 38), .line(13.4, 38.9)
        ], stroke: 0xfff0f2, width: 0.65, on: leftArm)
        paint([
            .move(13.1, 39.5), .curve(13.9, 39.4, 15.5, 40, 16, 40.1), .curve(16.5, 41.1, 16.2, 42.6, 15.1, 42.7),
            .curve(13.2, 43, 12.5, 42.2, 12.8, 41), .close
        ], gradient: (15, 10, 27, 40, [0xfff1da, 0xffd1bc, 0xefa197]), stroke: 0x32204f, width: 0.55, on: leftArm)
        paint([
            .move(14.85, 41.1), .quad(15.25, 41.8, 15.1, 42.3)
        ], stroke: 0xb96f77, width: 0.32, on: leftArm)
        root.addSublayer(rightArm)
        paint([
            .move(29.5, 30), .curve(31.5, 29, 33.5, 29.5, 33.7, 31), .line(35.3, 38.8),
            .line(34.4, 40.4), .line(31.1, 39.7), .quad(29.6, 34, 29.5, 30),
            .close
        ], gradient: (15, 29, 33, 40, [0xffb4d7, 0xe775a9, 0xa94382]), stroke: 0x32204f, width: 0.78, on: rightArm)
        paint([
            .move(31.3, 38), .line(34.6, 38.9)
        ], stroke: 0xfff0f2, width: 0.65, on: rightArm)
        paint([
            .move(32.1, 39.5), .curve(32.9, 39.4, 34.5, 40, 35, 40.1), .curve(35.5, 41.1, 35.2, 42.6, 34.1, 42.7),
            .curve(32.2, 43, 31.5, 42.2, 31.8, 41), .close
        ], gradient: (15, 10, 27, 40, [0xfff1da, 0xffd1bc, 0xefa197]), stroke: 0x32204f, width: 0.55, on: rightArm)
        paint([
            .move(33.85, 41.1), .quad(34.25, 41.8, 34.1, 42.3)
        ], stroke: 0xb96f77, width: 0.32, on: rightArm)
        paint([
            .move(21, 27), .line(27, 27), .line(31.8, 30),
            .line(30, 34.5), .line(30.2, 39), .curve(27, 40, 25.5, 39.5, 24, 38.4),
            .curve(22.2, 39.9, 20, 40, 17.8, 39), .line(18.4, 34.5), .line(16.2, 30),
            .line(21, 27), .close
        ], gradient: (15, 29, 33, 40, [0xffb4d7, 0xe775a9, 0xa94382]), stroke: 0x32204f, width: 0.9)
        paint([
            .move(22, 27), .line(26, 27), .line(27, 31),
            .line(24, 35), .line(21, 31), .close
        ], fill: 0xfff1ee, stroke: 0x32204f, width: 0.58)
        paint([
            .move(22.4, 29), .line(25.6, 29), .line(24, 31.5),
            .close
        ], fill: 0xbf4c84, stroke: 0x32204f, width: 0.36)
        paint([
            .move(20.7, 27.7), .line(18.7, 30.1), .line(20.1, 31.2),
            .line(19.4, 32.2), .line(23.5, 35), .close
        ], fill: 0xffbad8, stroke: 0x32204f, width: 0.52)
        paint([
            .move(27.3, 27.7), .line(29.3, 30.1), .line(27.9, 31.2),
            .line(28.6, 32.2), .line(24.5, 35), .close
        ], fill: 0xf79ac6, stroke: 0x32204f, width: 0.52)
        paint([
            .move(24, 35), .line(24, 38.4)
        ], stroke: 0x893961, width: 0.38)
        paint([
            .oval(23.4, 35.1, 1.2, 1.25)
        ], fill: 0xffd67c, stroke: 0x32204f, width: 0.38)
        paint([
            .oval(23.4, 36.8, 1.2, 1.25)
        ], fill: 0xffd67c, stroke: 0x32204f, width: 0.38)
        paint([
            .move(18.9, 36.2), .line(21.1, 36.6)
        ], stroke: 0xffe0ec, width: 0.53)
        paint([
            .move(27.1, 36.6), .line(29.1, 36.2)
        ], stroke: 0xffe0ec, width: 0.53)
        paint([
            .oval(28.3, 33, 1.25, 1.25)
        ], fill: 0xffdf8b, stroke: 0x32204f, width: 0.38)

        // Лицо и серьги.
        paint([
            .oval(11.988, 16.936, 3.12, 4.38)
        ], fill: 0xf6b09d, stroke: 0x32204f, width: 0.528)
        paint([
            .oval(32.97, 16.936, 3.12, 4.38)
        ], fill: 0xf6b09d, stroke: 0x32204f, width: 0.528)
        paint([
            .move(13.548, 15.33), .curve(12.534, 6.57, 19.71, 5.11, 24, 5.475), .curve(29.85, 5.11, 35.31, 8.76, 34.374, 17.52),
            .curve(34.686, 22.995, 29.46, 27.448, 25.56, 28.47), .curve(24, 29.273, 22.44, 28.908, 20.958, 28.251), .curve(16.59, 26.28, 13.626, 22.63, 13.548, 15.33),
            .close
        ], gradient: (15, 10, 27, 40, [0xfff1da, 0xffd1bc, 0xefa197]), stroke: 0x32204f, width: 0.8)
        paint([
            .oval(12.69, 20.44, 1.326, 1.898)
        ], fill: 0xffe090, stroke: 0x32204f, width: 0.34)
        paint([
            .oval(33.984, 20.44, 1.326, 1.898)
        ], fill: 0xffe090, stroke: 0x32204f, width: 0.34)

        // Глаза двигаются вместе с ресницами и бликами.
        root.addSublayer(eyes)
        paint([
            .move(15.498, 18.761), .curve(15.732, 15.476, 19.476, 15.038, 21.426, 16.717), .curve(22.518, 20.586, 20.1, 22.484, 17.76, 21.681),
            .quad(16.278, 21.17, 15.498, 18.761), .close
        ], fill: 0xfff6fe, stroke: 0x32204f, width: 0.642, on: eyes)
        paint([
            .oval(17.253, 16.06, 3.822, 5.402)
        ], gradient: (17.253, 16.06, 17.253, 21.17, [0x44216e, 0x7844ba, 0xefa2fb]), stroke: 0x32204f, width: 0.325, on: eyes)
        paint([
            .oval(18.306, 16.863, 1.95, 3.175)
        ], fill: 0x321c4f, on: eyes)
        paint([
            .oval(17.526, 16.498, 1.638, 1.314)
        ], fill: 0xfff9ff, on: eyes)
        paint([
            .oval(19.788, 19.637, 0.78, 0.912)
        ], fill: 0xffe4fc, on: eyes)
        paint([
            .move(14.991, 17.301), .quad(15.498, 16.644, 16.746, 16.206), .curve(18.618, 15.367, 20.958, 15.95, 21.582, 17.009)
        ], stroke: 0x3a2354, width: 0.793, on: eyes)
        paint([
            .move(15.693, 16.753), .line(14.796, 16.06)
        ], stroke: 0x3a2354, width: 0.544, on: eyes)
        paint([
            .move(16.356, 15.841), .line(15.771, 15.111)
        ], stroke: 0x3a2354, width: 0.415, on: eyes)
        paint([
            .move(16.044, 14.198), .quad(17.838, 13.177, 20.334, 13.87)
        ], stroke: 0x73416f, width: 0.544, on: eyes)
        eyes.addSublayer(rightEye)
        paint([
            .move(26.262, 18.761), .curve(26.496, 15.476, 30.24, 15.038, 32.19, 16.717), .curve(33.282, 20.586, 30.864, 22.484, 28.524, 21.681),
            .quad(27.042, 21.17, 26.262, 18.761), .close
        ], fill: 0xfff6fe, stroke: 0x32204f, width: 0.642, on: rightEye)
        paint([
            .oval(28.017, 16.06, 3.822, 5.402)
        ], gradient: (28.017, 16.06, 28.017, 21.17, [0x44216e, 0x7844ba, 0xefa2fb]), stroke: 0x32204f, width: 0.325, on: rightEye)
        paint([
            .oval(29.07, 16.863, 1.95, 3.175)
        ], fill: 0x321c4f, on: rightEye)
        paint([
            .oval(28.29, 16.498, 1.638, 1.314)
        ], fill: 0xfff9ff, on: rightEye)
        paint([
            .oval(30.552, 19.637, 0.78, 0.912)
        ], fill: 0xffe4fc, on: rightEye)
        paint([
            .move(25.755, 17.301), .quad(26.262, 16.644, 27.51, 16.206), .curve(29.382, 15.367, 31.722, 15.95, 32.346, 17.009)
        ], stroke: 0x3a2354, width: 0.793, on: rightEye)
        paint([
            .move(26.457, 16.753), .line(25.56, 16.06)
        ], stroke: 0x3a2354, width: 0.544, on: rightEye)
        paint([
            .move(27.12, 15.841), .line(26.535, 15.111)
        ], stroke: 0x3a2354, width: 0.415, on: rightEye)
        paint([
            .move(26.808, 14.198), .quad(28.602, 13.177, 31.098, 13.87)
        ], stroke: 0x73416f, width: 0.544, on: rightEye)
        paint([
            .oval(14.718, 21.535, 4.056, 2.044)
        ], fill: 0xf3a2aa)
        paint([
            .oval(29.304, 21.535, 4.056, 2.044)
        ], fill: 0xf3a2aa)
        paint([
            .move(15.81, 22.119), .line(16.278, 22.776)
        ], stroke: 0xcd748a, width: 0.242)
        paint([
            .move(17.292, 22.119), .line(17.76, 22.776)
        ], stroke: 0xcd748a, width: 0.242)
        paint([
            .move(30.552, 22.119), .line(31.02, 22.776)
        ], stroke: 0xcd748a, width: 0.242)
        paint([
            .move(32.034, 22.119), .line(32.502, 22.776)
        ], stroke: 0xcd748a, width: 0.242)
        paint([
            .move(24, 20.002), .line(23.415, 21.352), .line(24.078, 21.681)
        ], stroke: 0xd58780, width: 0.393)
        paint([
            .move(22.128, 24.309), .quad(24, 25.696, 25.95, 24.163)
        ], stroke: 0x994567, width: 0.566)

        // Чёлка и заколка.
        paint([
            .move(11.208, 14.235), .curve(10.74, 8.03, 14.64, 4.088, 21.348, 3.358), .curve(29.07, 2.19, 36.948, 7.3, 37.026, 13.505),
            .curve(37.104, 15.33, 36.558, 17.155, 35.544, 18.834), .curve(35.856, 16.79, 34.53, 13.14, 32.58, 11.461), .curve(32.19, 12.775, 31.956, 14.235, 30.786, 14.673),
            .curve(29.226, 13.578, 28.056, 11.461, 27.744, 10.074), .curve(26.73, 11.68, 25.248, 13.578, 22.44, 15.184), .curve(22.908, 13.651, 23.22, 11.68, 22.986, 10.585),
            .curve(21.426, 13.286, 18.072, 14.6, 15.03, 15.038), .curve(13.86, 16.133, 13.158, 17.885, 13.314, 19.637), .curve(11.91, 19.053, 11.286, 16.133, 11.208, 14.235),
            .close
        ], gradient: (16.2, 3.65, 27.9, 16.79, [0xb984f0, 0x8852bd, 0x59337f]), stroke: 0x32204f, width: 0.785)
        paint([
            .move(13.47, 12.41), .curve(14.64, 7.008, 20.646, 4.307, 27.666, 5.183)
        ], stroke: 0xdfb3ff, width: 0.906)
        paint([
            .move(14.484, 13.87), .curve(15.888, 10.95, 19.944, 11.023, 22.674, 7.446)
        ], stroke: 0xba81eb, width: 0.528)
        paint([
            .move(24.39, 11.826), .curve(25.794, 10.804, 26.808, 8.76, 27.276, 6.716)
        ], stroke: 0xc68cf5, width: 0.491)
        paint([
            .move(29.46, 7.373), .curve(33.048, 8.395, 34.686, 11.242, 35.466, 14.089)
        ], stroke: 0xc389ed, width: 0.438)
        paint([
            .move(16.824, 8.03), .quad(17.994, 7.227, 19.164, 6.935)
        ], stroke: 0xffe3ff, width: 0.415)
        paint([
            .move(31.02, 9.344), .line(32.424, 8.687), .line(33.906, 11.096),
            .line(35.31, 8.687), .line(36.636, 9.49), .line(33.906, 13.213),
            .close
        ], gradient: (31.02, 8.76, 34.92, 13.14, [0xfff5b7, 0xedae50]), stroke: 0x32204f, width: 0.415)
        paint([
            .oval(31.8, 9.344, 0.663, 0.584)
        ], fill: 0xfffbe4)

        if coffee {
            paint([
                .oval(40, 33, 6, 5)
            ], fill: 0xffda83, stroke: 0x32204f, width: 1)
            paint([
                .move(34, 32), .line(43, 32), .line(42, 41),
                .line(35, 41), .close
            ], fill: 0xffda83, stroke: 0x32204f, width: 1)
        }
        let stars: [(CGFloat, CGFloat, CGFloat)] = [(5, 13, 2.6), (43, 9, 3.5), (45, 22, 1.8)]
        sparks.frame = bounds
        sparks.path = path(for: stars.flatMap { star -> [Segment] in
            let (x, y, radius) = star
            let corner = radius * 0.25
            return [
                .move(x, y - radius), .line(x + corner, y - corner), .line(x + radius, y),
                .line(x + corner, y + corner), .line(x, y + radius), .line(x - corner, y + corner),
                .line(x - radius, y), .line(x - corner, y - corner), .close,
            ]
        })
        sparks.fillColor = CompanionView.Palette.rgb(0xffda83).cgColor
        sparks.opacity = 0
        root.addSublayer(sparks)
    }

    func setWalking(_ on: Bool) {
        let limbs: [(CALayer, Double)] = [
            (leftLeg, 0.32), (rightLeg, -0.32), (leftArm, -0.22), (rightArm, 0.22),
        ]
        for (limb, angle) in limbs {
            if on {
                let stride = motion("transform.rotation.z", [0, angle, 0, -angle, 0], duration: 0.55)
                stride.repeatCount = .infinity
                limb.add(stride, forKey: "stride")
            } else {
                limb.removeAnimation(forKey: "stride")
            }
        }
    }

    func wave() {
        let wave = motion("transform.rotation.z", [0, 2, 1.72, 2.18, 1.72, 2, 0], duration: 1.35)
        wave.keyTimes = [0, 0.17, 0.28, 0.4, 0.52, 0.73, 1]
        rightArm.add(wave, forKey: "wave")
    }

    func react() {
        let wink = motion("transform.scale.y", [1, 0.1, 0.1, 1], duration: 0.85)
        wink.keyTimes = [0, 0.18, 0.73, 1]
        rightEye.add(wink, forKey: "wink")

        let shimmer = motion("opacity", [0, 1, 0.55, 0.95, 0], duration: 1.18)
        shimmer.keyTimes = [0, 0.18, 0.47, 0.63, 1]
        sparks.add(shimmer, forKey: "sparkles")
    }

    private func motion(_ keyPath: String, _ values: [Double], duration: CFTimeInterval) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return animation
    }
}
