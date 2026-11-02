import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// iTag App Icon: 渐变底 + 白色定位 pin + 镂空圆内的打卡勾
let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: space,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue  // 无 alpha 通道
)!

let blue = CGColor(srgbRed: 0.231, green: 0.510, blue: 0.965, alpha: 1)   // #3B82F6
let indigo = CGColor(srgbRed: 0.388, green: 0.400, blue: 0.945, alpha: 1) // #6366F1
let gradient = CGGradient(colorsSpace: space, colors: [blue, indigo] as CFArray, locations: [0, 1])!

// 原点在左下：从左上到右下的对角渐变
let gradientStart = CGPoint(x: 0, y: 1024)
let gradientEnd = CGPoint(x: 1024, y: 0)

func drawBackground() {}  // 保留占位避免下方引用报错（未再使用）

// 1) 背景渐变（全画布，无需裁剪）
ctx.drawLinearGradient(gradient, start: gradientStart, end: gradientEnd, options: [])

// 2) 白色定位 pin：圆 + 下三角尖
let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
let pinCenter = CGPoint(x: 512, y: 485)
let pinRadius: CGFloat = 235

ctx.setFillColor(white)
ctx.fillEllipse(
    in: CGRect(
        x: pinCenter.x - pinRadius, y: pinCenter.y - pinRadius,
        width: pinRadius * 2, height: pinRadius * 2
    )
)
ctx.move(
    to: CGPoint(
        x: pinCenter.x - pinRadius * cos(.pi / 6),
        y: pinCenter.y - pinRadius * 0.5
    )
)
ctx.addLine(to: CGPoint(x: 512, y: 96))
ctx.addLine(
    to: CGPoint(
        x: pinCenter.x + pinRadius * cos(.pi / 6),
        y: pinCenter.y - pinRadius * 0.5
    )
)
ctx.closePath()
ctx.fillPath()

// 3) 中心镂空：clip 到小圆后重画渐变
let holeRadius: CGFloat = 102
ctx.saveGState()
ctx.addEllipse(
    in: CGRect(
        x: pinCenter.x - holeRadius, y: pinCenter.y - holeRadius,
        width: holeRadius * 2, height: holeRadius * 2
    )
)
ctx.clip()
ctx.drawLinearGradient(gradient, start: gradientStart, end: gradientEnd, options: [])
ctx.restoreGState()

// 4) 镂空圆内的白色"打卡"勾
ctx.setStrokeColor(white)
ctx.setLineWidth(36)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: pinCenter.x - 52, y: pinCenter.y + 6))
ctx.addLine(to: CGPoint(x: pinCenter.x - 8, y: pinCenter.y - 38))
ctx.addLine(to: CGPoint(x: pinCenter.x + 56, y: pinCenter.y + 44))
ctx.strokePath()

// 导出 PNG
let image = ctx.makeImage()!
let url = URL(fileURLWithPath: "/tmp/appicon_1024.png") as CFURL
let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("written /tmp/appicon_1024.png")
