// Prints the CGWindowID of the largest normal window owned by the given pid (no screen access needed).
import CoreGraphics
import Foundation
guard CommandLine.arguments.count > 1, let pid = Int32(CommandLine.arguments[1]) else { exit(2) }
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let mine = list.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
let best = mine.max { a, b in
    let ra = a[kCGWindowBounds as String] as? [String: Double] ?? [:], rb = b[kCGWindowBounds as String] as? [String: Double] ?? [:]
    return (ra["Width"] ?? 0) * (ra["Height"] ?? 0) < (rb["Width"] ?? 0) * (rb["Height"] ?? 0)
}
guard let w = best, let id = w[kCGWindowNumber as String] as? Int else { exit(1) }
let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
print(id, Int(b["Width"] ?? 0), Int(b["Height"] ?? 0))
