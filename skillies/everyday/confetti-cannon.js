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
        .map(color => color.CGColor)
    const shapes = [[7, 14, 0], [9, 9, 0], [8, 8, 4]]
    const random = (low, high) => low + Math.random() * (high - low)
    const pick = list => list[Math.floor(Math.random() * list.length)]
    const now = $.CACurrentMediaTime()
    const life = 5, gravity = 0.6 * height, drag = 1.0

    // Each call to Cocoa from JavaScript costs: a few paths and turns are
    // made once and shared, each piece offset a little from its path.
    function settle(animation) {
        animation.duration = life
        animation.fillMode = $.kCAFillModeBoth
        animation.removedOnCompletion = false
        return animation
    }
    // A path shot toward `aim` under gravity and the air's drag, relative
    // to where its piece starts: ten points, joined in curves.
    function path(aim) {
        const angle = aim + random(-Math.PI / 10, Math.PI / 10)
        const speed = random(1.5, 2.6) * height
        let x = 0, y = 0, vx = Math.cos(angle) * speed, vy = Math.sin(angle) * speed
        const fine = 100, dt = life / fine, points = []
        for (let i = 0; i <= fine; i++) {
            if (i % 10 === 0) points.push($.NSValue.valueWithPoint($.NSMakePoint(x, y)))
            vx -= vx * drag * dt
            vy -= (gravity + vy * drag) * dt
            x += vx * dt
            y += vy * dt
        }
        const animation = $.CAKeyframeAnimation.animationWithKeyPath('position')
        animation.values = $(points)
        animation.calculationMode = $.kCAAnimationCubic
        animation.additive = true
        return settle(animation)
    }
    function turn(keyPath, low, high) {
        const animation = $.CABasicAnimation.animationWithKeyPath(keyPath)
        animation.fromValue = $(0)
        animation.toValue = $(random(low, high))
        return settle(animation)
    }
    const cannons = [{ x: 0, aim: Math.PI * 0.36, paths: [] }, { x: width, aim: Math.PI * 0.64, paths: [] }]
    const spins = [], flips = []
    function more(count) {
        for (let i = 0; i < count; i++) {
            cannons.forEach(cannon => cannon.paths.push(path(cannon.aim)))
            // Spinning flat, and turning over as it falls: paper flutters.
            spins.push(turn('transform.rotation.z', -12, 12))
            flips.push(turn('transform.rotation.x', 4, 16))
        }
    }

    function piece(cannon) {
        const [w, h, radius] = pick(shapes)
        const layer = $.CALayer.layer
        layer.bounds = $.NSMakeRect(0, 0, w, h)
        if (radius) layer.cornerRadius = radius
        layer.backgroundColor = pick(colors)
        layer.position = $.NSMakePoint(cannon.x + random(-70, 70), random(-80, -20))
        const begin = now + random(0, 0.35)
        for (const animation of [pick(cannon.paths), pick(spins), pick(flips)]) {
            animation.beginTime = begin
            layer.addAnimationForKey(animation, $())
        }
        view.layer.addSublayer(layer)
    }

    const wait = seconds => $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(seconds))
    // The first pieces on screen at once; the rest made while they fly.
    more(4)
    for (let i = 0; i < 20; i++) cannons.forEach(piece)
    window.orderFrontRegardless
    wait(0.01)
    more(28)
    for (let i = 0; i < 90; i++) cannons.forEach(piece)
    // The last of it fades as it falls away.
    wait(3.8)
    for (let step = 1; step <= 12; step++) {
        window.alphaValue = 1 - step / 12
        wait(0.1)
    }
    window.orderOut($())
}
