# Repository for SVG2Keynote GUI

[Jonathan Lamperth](https://www.linkedin.com/in/jonathan-lamperth-7059b418a) and [Christian Holz](https://www.christianholz.net)<br/>
[Sensing, Interaction & Perception Lab](https://siplab.org) <br/>
Department of Computer Science, ETH Zürich

This is the repository for SVG2Keynote GUI, a macOS menu bar utility for previewing Scalable Vector Graphics and pasting them into Apple Keynote as editable native Keynote shapes.
This fork is a self-contained AppKit/WebKit + Objective-C/C++ app. It builds the Keynote clipboard codec directly from source in-tree, without the old prebuilt Intel-only static archives.

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

Then just open the `.xcodeproj` file with Xcode and build. This produces a self-contained `SVGMenuBar.app` that does not depend on external Homebrew libraries, Inkscape, or the old vendored static archives.

## Option 2 - Run the built app bundle

After building, launch the generated app from Xcode's Products folder or from `DerivedData`.

# Using the tool

Once the app has launched you should see the following icon in your toolbar:

<img src="img/icon.png"/>


Once clicking on the icon you will be greeted with the following popover:

<img src="img/readme_1_tool.png"/>


Here the UI should be pretty straightforward.

1. Use the button "Open SVG File" to select the file which you would like to insert into Keynote.
2. If needed, copy a primitive Keynote shape and press "Resync Compatibility" to learn the clipboard profile of that Keynote version.
3. Press "Copy Keynote Shapes" to place editable native Keynote data on the clipboard.
4. Paste into Keynote with `CMD + V`.
5. Use "Save Clipboard..." to export Keynote vector clipboard data back to SVG, or clipboard images back to PNG.


# What works and what doesn't?

### Working

- Building directly from source on modern Xcode without Homebrew libraries.
- Previewing local SVG files with native system frameworks.
- Copying editable native Keynote shapes to the clipboard.
- Learning and reusing compatibility profiles from real Keynote clipboard samples.
- Exporting Keynote vector clipboard content back to SVG.

### Not yet working

- Some private iWork clipboard details may still vary across Keynote releases and may need a fresh compatibility resync.
- SVG features that depend on browser/file access quirks may still need manual cleanup.

# How was this tool created?

The current app is a small Objective-C AppKit/WebKit utility. It renders the SVG in a native `WKWebView`, converts the geometry into private iWork/Keynote protobuf archives, and writes native Keynote clipboard data using the same pasteboard families that Keynote itself emits.

## Possible future developments

- [ ]  Drag-and-drop functionality
- [ ]  Get SVG from clipboard functionality
- [ ]  General code optimizations
- [ ]  Use a more advanced SVG parsing library.
