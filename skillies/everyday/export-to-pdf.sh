#!/bin/sh
# @skilli.schemaVersion 1
# @skilli.title Export to PDF
# @skilli.mode silent
# @skilli.packageName Everyday
# @skilli.description Export the document you are in as a PDF to Documents, then open Documents in Finder. skil.li does both steps in the apps for you, each asked first until you choose Always.
# MIT License
#
# Copyright (c) 2026 skil.li contributors
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Each line opens a skilli://do link: "do it here" toward a goal, written as
# you would ask it in Ask, in the app the link names (else the one you are in).
# skil.li runs them one at a time, in order: Finder waits for the export, and
# is dropped if you deny or stop it. Always on the export trusts it in any
# app (its link names none); on the Finder step, in Finder only. Settings →
# Catalog → Trusted Links lists both.
#
# Needs: skil.li 0.1.4 or later, allowed in Accessibility, with an SI that
# chooses in Settings → SI Accounts. Works in apps whose File menu exports a
# PDF (tried in TextEdit and Preview).
# Network: skil.li reads the window to find each step; its words, and at times
# its picture, go to that SI.
# Effects: a new PDF in Documents. A file already there is never replaced
# without asking: skil.li asks before it presses Replace.
/usr/bin/open 'skilli://do?goal=export%20as%20PDF%20to%20my%20Documents%20folder'
/usr/bin/open 'skilli://do?app=Finder&goal=open%20the%20Documents%20folder%20from%20the%20Go%20menu'
