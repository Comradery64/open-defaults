// Usage: swift scripts/window-shot.swift <out.png> [owner-name, default "Open Defaults"]
//        swift scripts/window-shot.swift --bounds   prints "x y w h" of the window, no capture
// Captures the first on-screen layer-0 window owned by owner-name.
import Foundation
import CoreGraphics

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: window-shot.swift <out.png> [owner-name]")
    exit(2)
}
let outPath = args[1]
let owner = args.count >= 3 ? args[2] : "Open Defaults"

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let match = windows.first {
    ($0[kCGWindowOwnerName as String] as? String) == owner && ($0[kCGWindowLayer as String] as? Int) == 0
}
guard let windowID = match?[kCGWindowNumber as String] as? Int else {
    print("no window")
    exit(1)
}
if outPath == "--bounds" {
    let b = match?[kCGWindowBounds as String] as? [String: Double] ?? [:]
    print(["X", "Y", "Width", "Height"].map { String(Int(b[$0] ?? 0)) }.joined(separator: " "))
    exit(0)
}

let shot = Process()
shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
shot.arguments = ["-x", "-o", "-l", String(windowID), outPath]
do {
    try shot.run()
} catch {
    print("capture failed: \(error)")
    exit(1)
}
shot.waitUntilExit()
guard shot.terminationStatus == 0 else {
    print("capture failed: screencapture exit \(shot.terminationStatus)")
    exit(1)
}
print("saved \(outPath)")
