// Prints "id x y w h" (points, global, top-left origin) for each on-screen normal window of a pid, largest first.
import CoreGraphics
import Foundation
let pid = Int32(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let rows = list.compactMap { w -> (Int, Double, Double, Double, Double)? in
    guard (w[kCGWindowOwnerPID as String] as? Int32) == pid, (w[kCGWindowLayer as String] as? Int) == 0,
          let id = w[kCGWindowNumber as String] as? Int, let b = w[kCGWindowBounds as String] as? [String: Double] else { return nil }
    let (x, y, ww, hh) = (b["X"] ?? 0, b["Y"] ?? 0, b["Width"] ?? 0, b["Height"] ?? 0)
    return ww * hh > 0 ? (id, x, y, ww, hh) : nil
}.sorted { $0.3 * $0.4 > $1.3 * $1.4 }
for r in rows { print(r.0, Int(r.1), Int(r.2), Int(r.3), Int(r.4)) }
