#!/usr/bin/swift
// @skilli.schemaVersion 1
// @skilli.title Confetti Cannon
// @skilli.mode silent
// @skilli.packageName Everyday
// @skilli.icon 🎉
// @skilli.description Fire confetti from the bottom corners of the screen the pointer is on. Clicks go through it; gone after five seconds. Give it a key in Settings → Keys → Add Shortcut, under Skillies. Needs Swift, which comes with Xcode or its Command Line Tools.
// MIT License
//
// Copyright (c) 2026 skil.li contributors
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import AppKit
import QuartzCore

// A see-through window over the screen the pointer is on, above every app
// and full-screen space, that never takes a click or the keyboard.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let pointer = NSEvent.mouseLocation
guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main else {
    print("No screen to fire on.")
    exit(1)
}
let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
window.isOpaque = false
window.backgroundColor = .clear
window.hasShadow = false
window.ignoresMouseEvents = true
window.level = .screenSaver
window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
window.setFrame(screen.frame, display: false)
let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
view.wantsLayer = true
window.contentView = view

// One piece of paper: a strip, a square or a dot, drawn at the screen's scale.
let scale = screen.backingScaleFactor
func piece(_ color: NSColor, _ size: CGSize, round: Bool) -> CGImage? {
    let width = Int(size.width * scale), height = Int(size.height * scale)
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    let rect = CGRect(x: 0, y: 0, width: width, height: height)
    context.setFillColor(color.cgColor)
    if round { context.fillEllipse(in: rect) } else { context.fill(rect) }
    return context.makeImage()
}

let colors: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemBlue, .systemPurple, .systemPink]
let shapes: [(CGSize, Bool)] = [(CGSize(width: 7, height: 14), false), (CGSize(width: 9, height: 9), false), (CGSize(width: 8, height: 8), true)]

// A cannon in a bottom corner, aimed up and toward the middle. The layer's
// y axis points up: 0 is to the right, π/2 straight up.
func cannon(at x: CGFloat, aim: CGFloat) -> CAEmitterLayer {
    let emitter = CAEmitterLayer()
    emitter.frame = view.bounds
    emitter.contentsScale = scale
    emitter.emitterPosition = CGPoint(x: x, y: -20)
    emitter.emitterShape = .point
    emitter.beginTime = CACurrentMediaTime()
    emitter.emitterCells = colors.flatMap { color in
        shapes.compactMap { size, round -> CAEmitterCell? in
            guard let image = piece(color, size, round: round) else { return nil }
            let cell = CAEmitterCell()
            cell.contents = image
            cell.contentsScale = scale
            cell.birthRate = 14
            cell.lifetime = 6
            cell.velocity = 0.95 * screen.frame.height
            cell.velocityRange = 0.35 * screen.frame.height
            cell.emissionLongitude = aim
            cell.emissionRange = .pi / 10
            cell.yAcceleration = -0.5 * screen.frame.height
            cell.spin = 3
            cell.spinRange = 10
            cell.scaleRange = 0.35
            return cell
        }
    }
    return emitter
}

let width = screen.frame.width
let cannons = [cannon(at: 0, aim: .pi * 0.36), cannon(at: width, aim: .pi * 0.64)]
cannons.forEach { view.layer?.addSublayer($0) }
window.orderFrontRegardless()

// One burst, then the paper falls; the last of it fades as it leaves.
DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
    cannons.forEach { $0.birthRate = 0 }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 3.8) {
    NSAnimationContext.runAnimationGroup({ context in
        context.duration = 1.2
        window.animator().alphaValue = 0
    }, completionHandler: { exit(0) })
}
app.run()
