//
//  EvidenceThreadStoreTests.swift
//  OpenIntelligenceTests
//

import XCTest
@testable import OpenIntelligence

final class EvidenceThreadStoreTests: XCTestCase {
    var store: EvidenceThreadStore!
    var testContainerId: UUID!
    var testThread: EvidenceThread!
    
    override func setUpWithError() throws {
        store = EvidenceThreadStore()
        testContainerId = UUID()
        
        let message = EvidenceThreadMessage(role: .user, content: "Hello, testing!")
        testThread = EvidenceThread(
            containerId: testContainerId,
            title: "Test Thread",
            messages: [message]
        )
    }

    override func tearDownWithError() throws {
        // Cleanup the test threads
        if let threads = try? store.listThreads(containerId: testContainerId) {
            for thread in threads {
                try? store.deleteThread(id: thread.id, containerId: testContainerId)
            }
        }
    }

    func testSerializationAndDeserialization() throws {
        // Save the thread
        try store.saveThread(testThread)
        
        // Retrieve the thread
        let loadedThread = try store.getThread(id: testThread.id, containerId: testContainerId)
        
        // Verify properties
        XCTAssertEqual(loadedThread.id, testThread.id)
        XCTAssertEqual(loadedThread.containerId, testThread.containerId)
        XCTAssertEqual(loadedThread.title, "Test Thread")
        XCTAssertEqual(loadedThread.messages.count, 1)
        XCTAssertEqual(loadedThread.messages.first?.content, "Hello, testing!")
        XCTAssertEqual(loadedThread.messages.first?.role, .user)
    }

    func testListThreads() throws {
        // Save two threads
        try store.saveThread(testThread)
        
        let secondThread = EvidenceThread(containerId: testContainerId, title: "Second Thread")
        try store.saveThread(secondThread)
        
        let threads = try store.listThreads(containerId: testContainerId)
        XCTAssertEqual(threads.count, 2)
        
        let titles = threads.map { $0.title }
        XCTAssertTrue(titles.contains("Test Thread"))
        XCTAssertTrue(titles.contains("Second Thread"))
    }
    
    func testDeleteThread() throws {
        try store.saveThread(testThread)
        XCTAssertEqual(try store.listThreads(containerId: testContainerId).count, 1)
        
        try store.deleteThread(id: testThread.id, containerId: testContainerId)
        XCTAssertEqual(try store.listThreads(containerId: testContainerId).count, 0)
        
        // Ensure getting a deleted thread throws an error
        XCTAssertThrowsError(try store.getThread(id: testThread.id, containerId: testContainerId)) { error in
            XCTAssertEqual(error as? EvidenceThreadStore.Error, .threadNotFound)
        }
    }
    
    func testIsolation() throws {
        // Create thread in container A
        let containerA = UUID()
        let threadA = EvidenceThread(containerId: containerA, title: "Thread A")
        try store.saveThread(threadA)
        
        // Create thread in container B
        let containerB = UUID()
        let threadB = EvidenceThread(containerId: containerB, title: "Thread B")
        try store.saveThread(threadB)
        
        // List container A
        let listA = try store.listThreads(containerId: containerA)
        XCTAssertEqual(listA.count, 1)
        XCTAssertEqual(listA.first?.id, threadA.id)
        
        // List container B
        let listB = try store.listThreads(containerId: containerB)
        XCTAssertEqual(listB.count, 1)
        XCTAssertEqual(listB.first?.id, threadB.id)
        
        // Cleanup
        try store.deleteThread(id: threadA.id, containerId: containerA)
        try store.deleteThread(id: threadB.id, containerId: containerB)
    }
    
    func testConcurrency() async throws {
        let concurrentStore = EvidenceThreadStore()
        let container = UUID()
        let iterations = 100
        
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    let thread = EvidenceThread(containerId: container, title: "Concurrent Thread \(i)")
                    try? concurrentStore.saveThread(thread)
                }
            }
        }
        
        let loadedThreads = try concurrentStore.listThreads(containerId: container)
        XCTAssertEqual(loadedThreads.count, iterations)
        
        // Cleanup
        for thread in loadedThreads {
            try concurrentStore.deleteThread(id: thread.id, containerId: container)
        }
    }
}
