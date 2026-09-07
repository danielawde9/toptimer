#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct IconVariant {
  let filename: String
  let pixels: Int
}

let variants = [
  IconVariant(filename: "icon_16x16.png", pixels: 16),
  IconVariant(filename: "icon_16x16@2x.png", pixels: 32),
  IconVariant(filename: "icon_32x32.png", pixels: 32),
  IconVariant(filename: "icon_32x32@2x.png", pixels: 64),
  IconVariant(filename: "icon_128x128.png", pixels: 128),
  IconVariant(filename: "icon_128x128@2x.png", pixels: 256),
  IconVariant(filename: "icon_256x256.png", pixels: 256),
  IconVariant(filename: "icon_256x256@2x.png", pixels: 512),
  IconVariant(filename: "icon_512x512.png", pixels: 512),
  IconVariant(filename: "icon_512x512@2x.png", pixels: 1024),
]

func drawIcon(size: Int) throws -> CGImage {
  let space = CGColorSpaceCreateDeviceRGB()
  guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  ) else {
    throw CocoaError(.coderInvalidValue)
  }

  let scale = CGFloat(size)
  context.setFillColor(CGColor(red: 0.035, green: 0.055, blue: 0.11, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: scale, height: scale))

  let center = CGPoint(x: scale * 0.5, y: scale * 0.5)
  let radius = scale * 0.31
  context.setStrokeColor(CGColor(red: 0.435, green: 0.608, blue: 1, alpha: 1))
  context.setLineWidth(scale * 0.075)
  context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
  context.strokePath()

  context.setStrokeColor(CGColor(gray: 1, alpha: 1))
  context.setLineCap(.round)
  context.setLineWidth(scale * 0.055)
  context.move(to: center)
  context.addLine(to: CGPoint(x: scale * 0.5, y: scale * 0.72))
  context.strokePath()
  context.move(to: center)
  context.addLine(to: CGPoint(x: scale * 0.67, y: scale * 0.42))
  context.strokePath()

  context.setFillColor(CGColor(red: 1, green: 0.714, blue: 0.353, alpha: 1))
  context.fillEllipse(
    in: CGRect(
      x: center.x - scale * 0.055,
      y: center.y - scale * 0.055,
      width: scale * 0.11,
      height: scale * 0.11))

  guard let image = context.makeImage() else { throw CocoaError(.coderInvalidValue) }
  return image
}

func writePNG(_ image: CGImage, to url: URL) throws {
  guard let destination = CGImageDestinationCreateWithURL(
    url as CFURL, UTType.png.identifier as CFString, 1, nil)
  else {
    throw CocoaError(.fileWriteUnknown)
  }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

guard CommandLine.arguments.count == 2 else {
  FileHandle.standardError.write(Data("Usage: generate-icon.swift <output-directory>\n".utf8))
  exit(64)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconset = outputDirectory.appendingPathComponent("TopTimer.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: false)
for variant in variants {
  try writePNG(try drawIcon(size: variant.pixels), to: iconset.appendingPathComponent(variant.filename))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", outputDirectory.appendingPathComponent("TopTimer.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
