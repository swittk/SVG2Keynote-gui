# Repository for SVG2Keynote GUI

[Jonathan Lamperth](https://www.linkedin.com/in/jonathan-lamperth-7059b418a) and [Christian Holz](https://www.christianholz.net)<br/>
[Sensing, Interaction & Perception Lab](https://siplab.org) <br/>
Department of Computer Science, ETH Zürich

This is the repository for SVG2Keynote GUI, a macOS menu bar utility for previewing Scalable Vector Graphics and pasting them into Apple Keynote as vector PDF content.
This fork no longer relies on the old protobuf-based private Keynote pasteboard format. It is now a self-contained AppKit/WebKit app that previews an SVG and copies a vector PDF to the clipboard for pasting into Keynote.

[SVG2Keynote project page](https://siplab.org/releases/SVG2Keynote)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)


# Demo

https://user-images.githubusercontent.com/56671993/132128636-555d457e-9113-4fcb-b430-506e5e4449ff.mov



# Installation Process

## Prerequisites

- Xcode

## Option 1 - Compile with Xcode (Best Choice)

First clone the repository:

```bash
git clone https://github.com/eth-siplab/SVG2Keynote-gui
```

Then just open the `.xcodeproj` file with Xcode and build. This produces a self-contained `KeynoteSVGUI.app` that does not depend on protobuf, Inkscape, or the vendored static archives.

## Option 2 - Run the built app bundle

After building, launch the generated app from Xcode's Products folder or from `DerivedData`.

# Using the tool

Once the app has launched you should see the following icon in your toolbar:

<img src="img/icon.png"/>


Once clicking on the icon you will be greeted with the following popover:

<img src="img/readme_1_tool.png"/>


Here the UI should be pretty straightforward.

1. Use the button "Open SVG File" to select the file which you would like to insert into keynote.
2. Press "Copy PDF for Keynote" to place a vector PDF on the clipboard.
3. Paste into Keynote with `CMD + V`.

This version intentionally avoids the private protobuf-based iWork pasteboard payloads. The pasted result stays vector, but it is handled by Keynote as PDF content rather than as editable native Keynote shapes.


# What works and what doesn't?

### Working

- Building directly from source on modern Xcode without Homebrew libraries.
- Previewing local SVG files with native system frameworks.
- Copying a vector PDF to the clipboard and pasting it into Keynote.

### Not yet working

- Native editable Keynote shape payload generation.
- SVG features that depend on browser/file access quirks may still need manual cleanup.

# How was this tool created?

The current app is a small Objective-C AppKit/WebKit utility. It renders the SVG in a native `WKWebView` and writes PDF data to the clipboard using the standard macOS pasteboard types that Keynote already understands.

## Possible future developments

- [ ]  Drag-and-drop functionality
- [ ]  Get SVG from clipboard functionality
- [ ]  General code optimizations
- [ ]  Use a more advanced SVG parsing library.
