#!/bin/sh
# @skilli.schemaVersion 1
# @skilli.title Project status
# @skilli.mode fullOutput
# @skilli.packageName Developer
# @skilli.description Show the current branch and changed files in a Git project.
# @skilli.argument1 {"type":"text","placeholder":"Project folder"}
# @skilli.requires xcode-tools
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
set -eu
project=${1:?Choose a project folder}
case "$project" in '~/'*) project="$HOME/${project#\~/}";; esac
/usr/bin/git -C "$project" status --short --branch
