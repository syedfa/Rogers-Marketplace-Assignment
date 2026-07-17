#!/usr/bin/env swift
// Generates 24 solid-color placeholder JPEGs for the mock server, entirely
// offline (no network, no image assets, no third-party dependencies) using
// only CoreGraphics + ImageIO, which ship with macOS.
//
// Usage: swift scripts/generate-placeholder-images.swift

import CoreGraphics
import ImageIO
import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

let imageCount = 24
let size = 800
let outputDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("mock-server/public/images")

try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

// One base hue per marketplace category, cycling through 3 lightness
// variants so `placeholder-0.jpg`...`placeholder-23.jpg` aren't all
// identical within a category.
let baseHues: [CGFloat] = [0.55, 0.32, 0.08, 0.0, 0.28, 0.75, 0.12, 0.62]

func color(for index: Int) -> CGColor {
    let hue = baseHues[index % baseHues.count]
    let variant = index / baseHues.count
    let brightness: CGFloat = [0.55, 0.7, 0.85][variant % 3]
    return CGColor(
        colorSpace: CGColorSpaceCreateDeviceRGB(),
        components: hsbComponents(hue: hue, saturation: 0.45, brightness: brightness)
    ) ?? CGColor(gray: 0.5, alpha: 1)
}

func hsbComponents(hue: CGFloat, saturation: CGFloat, brightness: CGFloat) -> [CGFloat] {
    let i = Int(hue * 6)
    let f = hue * 6 - CGFloat(i)
    let p = brightness * (1 - saturation)
    let q = brightness * (1 - f * saturation)
    let t = brightness * (1 - (1 - f) * saturation)
    let rgb: (CGFloat, CGFloat, CGFloat)
    switch i % 6 {
    case 0: rgb = (brightness, t, p)
    case 1: rgb = (q, brightness, p)
    case 2: rgb = (p, brightness, t)
    case 3: rgb = (p, q, brightness)
    case 4: rgb = (t, p, brightness)
    default: rgb = (brightness, p, q)
    }
    return [rgb.0, rgb.1, rgb.2, 1.0]
}

for index in 0..<imageCount {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { continue }

    let fillColor = color(for: index)
    context.setFillColor(fillColor)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))

    // A soft translucent circle for a bit of visual texture so grid cells
    // aren't perfectly flat.
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.12))
    let circleRect = CGRect(x: CGFloat(size) * 0.15, y: CGFloat(size) * 0.15, width: CGFloat(size) * 0.7, height: CGFloat(size) * 0.7)
    context.fillEllipse(in: circleRect)

    guard let image = context.makeImage() else { continue }

    let outputURL = outputDirectory.appendingPathComponent("placeholder-\(index).jpg")
    guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, "public.jpeg" as CFString, 1, nil) else {
        continue
    }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
    CGImageDestinationFinalize(destination)
}

print("Wrote \(imageCount) placeholder images to \(outputDirectory.path)")
