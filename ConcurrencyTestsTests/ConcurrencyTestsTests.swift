//
//  ConcurrencyTestsTests.swift
//  ConcurrencyTestsTests
//
//  Created by Max Gribov on 07.08.2023.
//

import XCTest
@testable import ConcurrencyTests

struct FeedItem: Equatable {
    
    let id: UUID
    let name: String
}

protocol FeedClient {
    
    func getItems(from: URL) async throws -> [FeedItem]
}

final class FeedItemsLoader {
    
    private let client: any FeedClient
    
    init(client: any FeedClient) {
        
        self.client = client
    }
    
    static let feedURL = URL(string: "https://some-url.com")!
    
    func loadItems() async throws -> [FeedItem] {
        
        try await client.getItems(from: FeedItemsLoader.feedURL)
    }
}

final class ConcurrencyTestsTests: XCTestCase {

    func test_loadItems_returnsResultIfSUTInstanceNotDeinited() async throws {
        
        swift_task_enqueueGlobal_hook = { job, _ in
            MainActor.shared.enqueue(job)
        }
        
        let client = FeedClientSpy()
        let sut = FeedItemsLoader(client: client)
        let expectedResult = [FeedItem(id: UUID(), name: "Test")]
        
        let task = Task { [weak sut] in
            
            try await sut?.loadItems()
        }
        
        await Task.yield() //suspend current task for a little bit, to allow other async tasks do their job
        client.response(with: expectedResult)
        let result = try await task.value
                
        XCTAssertEqual(result, expectedResult)
    }
    
    func test_loadItems_returnsNilAfterSUTInstanceDeinited() async throws {
        
        swift_task_enqueueGlobal_hook = { job, _ in
            MainActor.shared.enqueue(job)
        }
        
        let client = FeedClientSpy()
        var sut: FeedItemsLoader? = FeedItemsLoader(client: client)
        
        let task = Task { [weak sut] in
            
            try await sut?.loadItems()
        }
        
        sut = nil
        await Task.yield() //suspend current task for a little bit, to allow other async tasks do their job
        client.response(with: [.init(id: UUID(), name: "Test")])
        let result = try await task.value
        
        XCTAssertNil(result)
    }
}

private final class FeedClientSpy: FeedClient {
    
    private let responseContinuation: AsyncStream<[FeedItem]>.Continuation
    private let responseStream: AsyncStream<[FeedItem]>
    
    init() {
        
        var responseContinuation: AsyncStream<[FeedItem]>.Continuation!
        self.responseStream = AsyncStream { responseContinuation = $0 }
        self.responseContinuation = responseContinuation
    }
    
    func getItems(from: URL) async throws -> [FeedItem] {
        
        await responseStream.first(where: { _ in true })!
    }
    
    func response(with items: [FeedItem]) {
        
        responseContinuation.yield(items)
    }
}
