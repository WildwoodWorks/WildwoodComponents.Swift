// NotificationService is a client-side toast queue (@MainActor @Observable),
// the Swift analog of @wildwood/core's notification service.

import Foundation
import Testing
@testable import WildwoodCore

@MainActor
struct NotificationServiceTests {
    @Test func showAppendsToastsWithIncrementingIds() {
        let service = NotificationService()

        let id1 = service.show("first", durationMs: 0)
        let id2 = service.show("second", durationMs: 0)

        #expect(service.toasts.count == 2)
        #expect(id1 == "1")
        #expect(id2 == "2")
        #expect(service.toasts.first?.message == "first")
    }

    @Test func errorToastIsStickyAndTypedError() throws {
        let service = NotificationService()

        let id = service.error("boom")

        let toast = try #require(service.toasts.first { $0.id == id })
        #expect(toast.type == .error)
        // Errors don't auto-dismiss.
        #expect(toast.duration == 0)
    }

    @Test func successWarningInfoCarryTheirType() {
        let service = NotificationService()

        let s = service.success("s")
        let w = service.warning("w")
        let i = service.info("i")

        #expect(service.toasts.first { $0.id == s }?.type == .success)
        #expect(service.toasts.first { $0.id == w }?.type == .warning)
        #expect(service.toasts.first { $0.id == i }?.type == .info)
    }

    @Test func dismissRemovesTheToast() {
        let service = NotificationService()
        let id = service.show("hi", durationMs: 0)

        service.dismiss(id)

        #expect(service.toasts.isEmpty)
    }

    @Test func clearRemovesAllToasts() {
        let service = NotificationService()
        service.show("a", durationMs: 0)
        service.show("b", durationMs: 0)

        service.clear()

        #expect(service.toasts.isEmpty)
    }
}
