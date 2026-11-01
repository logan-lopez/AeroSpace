// Times read-only AX calls into running apps, outside AeroSpace, to tell whether an app is
// slow at AX by itself. Usage: swift axprobe.swift <pid>... (the terminal running it needs the
// Accessibility permission; "trusted: false" and error -25211 mean it does not have it).
// Brief 01, 2026-11-01.
import ApplicationServices
import Foundation
print("trusted:", AXIsProcessTrusted())
func ms(_ b: () -> Void) -> Double { let t = DispatchTime.now().uptimeNanoseconds; b(); return Double(DispatchTime.now().uptimeNanoseconds - t) / 1e6 }
for arg in CommandLine.arguments.dropFirst() {
  let pid = pid_t(arg)!
  let app = AXUIElementCreateApplication(pid)
  var samples: [String: [Double]] = [:]
  for _ in 0..<15 {
    var v: CFTypeRef?
    var err = AXError.success
    samples["windows", default: []].append(ms { err = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &v) })
    if err != .success { print(pid, "windows err", err.rawValue) }
    var fw: CFTypeRef?
    samples["focusedWindow", default: []].append(ms { _ = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &fw) })
    if let wins = v as? [AXUIElement], let w = wins.first {
      var p: CFTypeRef?
      samples["position", default: []].append(ms { _ = AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &p) })
      samples["size", default: []].append(ms { _ = AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &p) })
      samples["fullscreen", default: []].append(ms { _ = AXUIElementCopyAttributeValue(w, "AXFullScreen" as CFString, &p) })
      samples["count", default: []].append(Double(wins.count))
    }
    usleep(100_000)
  }
  for (k, s) in samples.sorted(by: { $0.key < $1.key }) {
    let x = s.sorted()
    print(pid, k, String(format: "min %.1f  med %.1f  max %.1f", x.first!, x[x.count/2], x.last!))
  }
}
