@testable import AppBundle
import Common
import XCTest

final class FloatingWindowLayoutTest: XCTestCase {
    // Two monitors side by side: left 1000x800 at x = -1000, right (main) 2000x1000 at x = 0
    private let left = Rect(topLeftX: -1000, topLeftY: 200, width: 1000, height: 800)
    private let right = Rect(topLeftX: 0, topLeftY: 0, width: 2000, height: 1000)

    private func monitors(workspaceOnRight: Bool) -> [FloatingLayoutMonitor] {
        [
            FloatingLayoutMonitor(rect: left, visibleRect: left, showsWorkspace: !workspaceOnRight),
            FloatingLayoutMonitor(rect: right, visibleRect: right, showsWorkspace: workspaceOnRight),
        ]
    }

    func testAlreadyOnWorkspaceMonitor() {
        let window = Rect(topLeftX: 100, topLeftY: 100, width: 400, height: 300)
        XCTAssertNil(floatingWindowTopLeftOnWorkspaceMonitor(window, monitors(workspaceOnRight: true), right))
    }

    func testMovedKeepingProportionalPosition() {
        // Window at 10% x, 25% y of the left monitor
        let window = Rect(topLeftX: -900, topLeftY: 400, width: 200, height: 100)
        let topLeft = floatingWindowTopLeftOnWorkspaceMonitor(window, monitors(workspaceOnRight: true), right)
        assertEquals(topLeft, CGPoint(x: 200, y: 250))
    }

    func testMovedAndClampedInsideWorkspaceMonitor() {
        // Window near the right edge of the right monitor, too wide to keep its proportion on the left one
        let window = Rect(topLeftX: 1500, topLeftY: 900, width: 900, height: 300)
        let topLeft = floatingWindowTopLeftOnWorkspaceMonitor(window, monitors(workspaceOnRight: false), left)
        assertEquals(topLeft, CGPoint(x: -900, y: 700))
    }

    func testCenterOutsideAllMonitorsUsesNearest() {
        // Center far to the left of the left monitor: nearest is the left monitor, which shows the workspace
        let window = Rect(topLeftX: -3000, topLeftY: 300, width: 200, height: 100)
        XCTAssertNil(floatingWindowTopLeftOnWorkspaceMonitor(window, monitors(workspaceOnRight: false), left))
    }
}
