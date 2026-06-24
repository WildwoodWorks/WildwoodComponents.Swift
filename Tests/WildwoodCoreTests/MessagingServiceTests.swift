// MessagingService behavior mirrored from the JS messagingService tests:
// thread/message endpoints, Bool returns, and client-side draft storage.

import Foundation
import Testing
@testable import WildwoodCore

@MainActor
struct MessagingServiceTests {
    private func makeService(storage: (any WildwoodStorageAdapter)? = nil) -> (MessagingService, MockBackend) {
        let backend = MockBackend()
        let config = WildwoodConfig(baseUrl: backend.baseUrl, appId: "app-1", enableRetry: false)
        let http = WildwoodHttpClient(config: config, urlSession: backend.makeSession())
        return (MessagingService(http: http, storage: storage), backend)
    }

    private func jsonBody(_ req: RecordedRequest) throws -> [String: Any] {
        let data = try #require(req.body)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func getThreadReturnsNilOnError() async {
        let (service, _) = makeService() // no stub
        #expect(await service.getThread(threadId: "missing") == nil)
    }

    @Test func createThreadPostsTheThreadPayload() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/messaging/threads", .init(json: #"{"id":"thread-1"}"#))

        let thread = try await service.createThread(companyAppId: "cap-1", subject: "Subject", participantIds: ["u1", "u2"])

        #expect(thread.id == "thread-1")
        let req = try #require(backend.requests().first { $0.method == "POST" && $0.path == "/api/messaging/threads" })
        let body = try jsonBody(req)
        #expect(body["companyAppId"] as? String == "cap-1")
        #expect(body["subject"] as? String == "Subject")
        #expect(body["participantIds"] as? [String] == ["u1", "u2"])
    }

    @Test func editMessagePutsTheNewContent() async throws {
        let (service, backend) = makeService()
        backend.stub("PUT", "/api/messaging/messages/m1", .init(json: #"{"id":"m1"}"#))

        _ = try await service.editMessage(messageId: "m1", newContent: "updated")

        let req = try #require(backend.requests().first { $0.method == "PUT" && $0.path == "/api/messaging/messages/m1" })
        let body = try jsonBody(req)
        #expect(body["content"] as? String == "updated")
    }

    @Test func reactToMessagePostsTheEmoji() async throws {
        let (service, backend) = makeService()
        backend.stub("POST", "/api/messaging/messages/m1/reactions", .init(statusCode: 200))

        let ok = await service.reactToMessage(messageId: "m1", emoji: "👍")

        #expect(ok == true)
        let req = try #require(backend.requests().first { $0.path == "/api/messaging/messages/m1/reactions" })
        let body = try jsonBody(req)
        #expect(body["emoji"] as? String == "👍")
    }

    @Test func removeReactionDeletesFromTheReactionPath() async {
        let (service, backend) = makeService()
        // Use a plain token to keep the path encode/decode round-trip unambiguous.
        backend.stub("DELETE", "/api/messaging/messages/m1/reactions/thumbsup", .init(statusCode: 200))

        #expect(await service.removeReaction(messageId: "m1", emoji: "thumbsup") == true)
        #expect(backend.requests().contains { $0.method == "DELETE" && $0.path == "/api/messaging/messages/m1/reactions/thumbsup" })
    }

    @Test func deleteMessageReturnsFalseWhenRequestFails() async {
        let (service, _) = makeService() // no stub
        #expect(await service.deleteMessage(messageId: "m1") == false)
    }

    @Test func draftRoundtripsThroughStorageAndClears() {
        let storage = MemoryStorage()
        let (service, _) = makeService(storage: storage)

        service.saveDraft(threadId: "t1", content: "hello")

        #expect(service.getDraft(threadId: "t1")?.content == "hello")
        #expect(storage.getItem(WildwoodStorageKeys.draft(threadId: "t1")) != nil)

        service.clearDraft(threadId: "t1")
        #expect(service.getDraft(threadId: "t1") == nil)
    }
}
