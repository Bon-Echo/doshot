#!/usr/bin/env swift
//
// Programmatic AppIcon master PNG for DoShot.
// Renders a 1024×1024 rounded-square (macOS Big Sur+ shape) with a slate
// gradient background and a viewfinder-style mark in the center.
//
// Usage: swift Scripts/gen-icon.swift <output.png>
//

import AppKit
import CoreGraphics

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("usage: gen-icon.swift <output.png>\n".data(using: .utf8)!)
    exit(2)
}

let outputPath = CommandLine.arguments[1]
let sz: CGFloat = 1024

let image = NSImage(size: NSSize(width: sz, height: sz))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no cg context") }

// Background: macOS-shape rounded square clipped to the canvas.
let radius = sz * 0.2237
ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: sz, height: sz),
                   cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.clip()

// Slate vertical gradient (top → bottom).
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        CGColor(srgbRed: 0.176, green: 0.220, blue: 0.314, alpha: 1.0), // slate-700
        CGColor(srgbRed: 0.067, green: 0.094, blue: 0.153, alpha: 1.0)  // slate-900
    ] as CFArray,
    locations: [0.0, 1.0])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 0, y: sz),
                       end: CGPoint(x: 0, y: 0),
                       options: [])

// Viewfinder mark: four white corner L-brackets + center dot.
ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 0.95))
ctx.setFillColor(CGColor(gray: 1.0, alpha: 0.95))
ctx.setLineWidth(sz * 0.035)
ctx.setLineCap(.round)

let pad = sz * 0.24
let arm = sz * 0.13
let corners: [(CGPoint, CGPoint, CGPoint)] = [
    (CGPoint(x: pad,         y: sz - pad - arm), CGPoint(x: pad,        y: sz - pad), CGPoint(x: pad + arm,    y: sz - pad)),      // top-left
    (CGPoint(x: sz - pad - arm, y: sz - pad),    CGPoint(x: sz - pad,   y: sz - pad), CGPoint(x: sz - pad,     y: sz - pad - arm)), // top-right
    (CGPoint(x: sz - pad,    y: pad + arm),      CGPoint(x: sz - pad,   y: pad),      CGPoint(x: sz - pad - arm, y: pad)),         // bottom-right
    (CGPoint(x: pad + arm,   y: pad),            CGPoint(x: pad,        y: pad),      CGPoint(x: pad,          y: pad + arm))       // bottom-left
]
for (a, b, c) in corners {
    ctx.move(to: a)
    ctx.addLine(to: b)
    ctx.addLine(to: c)
    ctx.strokePath()
}

// Center dot.
let dotR = sz * 0.07
ctx.fillEllipse(in: CGRect(x: (sz - dotR * 2) / 2,
                            y: (sz - dotR * 2) / 2,
                            width: dotR * 2,
                            height: dotR * 2))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("failed to encode PNG")
}
try! png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath) (1024×1024)")
