#!/usr/bin/osascript -l JavaScript
// @skilli.schemaVersion 1
// @skilli.title Confetti Cannon
// @skilli.mode silent
// @skilli.showsRunning false
// @skilli.packageName Everyday
// @skilli.icon 🎉
// @skilli.description Fire confetti from the bottom corners of the screen the pointer is on. Clicks go through it; gone after five seconds. Give it a key in Settings → Keys → Add Shortcut, under Skillies. JavaScript for Automation: nothing to install.
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

ObjC.import('Cocoa')
ObjC.import('QuartzCore')

function run() {
    const app = $.NSApplication.sharedApplication
    app.setActivationPolicy($.NSApplicationActivationPolicyAccessory)

    // The screen the pointer is on.
    const pointer = $.NSEvent.mouseLocation
    const screen = $.NSScreen.screens.js.find(s => {
        const f = s.frame
        return pointer.x >= f.origin.x && pointer.x < f.origin.x + f.size.width
            && pointer.y >= f.origin.y && pointer.y < f.origin.y + f.size.height
    }) || $.NSScreen.mainScreen
    const frame = screen.frame
    const width = frame.size.width, height = frame.size.height

    // A see-through window above every app, that never takes a click.
    const window = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer(frame, 0, 2, false)
    window.opaque = false
    window.backgroundColor = $.NSColor.clearColor
    window.hasShadow = false
    window.ignoresMouseEvents = true
    window.level = 1000
    // canJoinAllSpaces | stationary | ignoresCycle | fullScreenAuxiliary
    window.collectionBehavior = 1 | 16 | 64 | 256
    window.setFrameDisplay(frame, false)
    const view = $.NSView.alloc.initWithFrame($.NSMakeRect(0, 0, width, height))
    view.wantsLayer = true
    window.contentView = view

    const colors = [$.NSColor.systemRedColor, $.NSColor.systemOrangeColor, $.NSColor.systemYellowColor, $.NSColor.systemGreenColor,
                    $.NSColor.systemTealColor, $.NSColor.systemBlueColor, $.NSColor.systemPurpleColor, $.NSColor.systemPinkColor]
    const shapes = [[7, 14, 0], [9, 9, 0], [8, 8, 4]]
    const random = (low, high) => low + Math.random() * (high - low)
    const now = $.CACurrentMediaTime()
    const life = 5, steps = 50, gravity = 0.6 * height, drag = 1.0

    // A piece of paper shot from (x0, 0) toward `aim`: its path under
    // gravity and the air's drag, sampled for a keyframe animation.
    function piece(x0, aim) {
        const [w, h, radius] = shapes[Math.floor(Math.random() * shapes.length)]
        const layer = $.CALayer.layer
        layer.bounds = $.NSMakeRect(0, 0, w, h)
        layer.cornerRadius = radius
        layer.backgroundColor = colors[Math.floor(Math.random() * colors.length)].CGColor
        const angle = aim + random(-Math.PI / 10, Math.PI / 10)
        const speed = random(1.5, 2.6) * height
        let x = x0, y = -20, vx = Math.cos(angle) * speed, vy = Math.sin(angle) * speed
        const dt = life / steps, points = []
        for (let i = 0; i <= steps; i++) {
            points.push($.NSValue.valueWithPoint($.NSMakePoint(x, y)))
            vx -= vx * drag * dt
            vy -= (gravity + vy * drag) * dt
            x += vx * dt
            y += vy * dt
        }
        layer.position = $.NSMakePoint(x0, -20)
        const delay = random(0, 0.25)
        const path = $.CAKeyframeAnimation.animationWithKeyPath('position')
        path.values = $(points)
        const spin = $.CABasicAnimation.animationWithKeyPath('transform.rotation.z')
        spin.fromValue = $(0)
        spin.toValue = $(random(-12, 12))
        // `transform.rotation.x` turns it over as it falls: paper flutters.
        const flip = $.CABasicAnimation.animationWithKeyPath('transform.rotation.x')
        flip.fromValue = $(0)
        flip.toValue = $(random(4, 16))
        for (const animation of [path, spin, flip]) {
            animation.beginTime = now + delay
            animation.duration = life
            animation.fillMode = $.kCAFillModeBoth
            animation.removedOnCompletion = false
            layer.addAnimationForKey(animation, $())
        }
        view.layer.addSublayer(layer)
    }

    for (let i = 0; i < 110; i++) {
        piece(0, Math.PI * 0.36)
        piece(width, Math.PI * 0.64)
    }
    window.orderFrontRegardless

    const wait = seconds => $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(seconds))
    // The last of it fades as it falls away.
    wait(3.8)
    for (let step = 1; step <= 12; step++) {
        window.alphaValue = 1 - step / 12
        wait(0.1)
    }
    window.orderOut($())
}
