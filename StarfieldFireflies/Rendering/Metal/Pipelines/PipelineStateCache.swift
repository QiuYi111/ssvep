//
//  PipelineStateCache.swift
//  StarfieldFireflies
//
//  Thread-safe dictionary cache for MTLRenderPipelineState objects.
//

import Metal
import Foundation

final class PipelineStateCache {

    private var cache: [String: MTLRenderPipelineState] = [:]
    private let lock = NSLock()

    func getOrCreate(name: String, factory: () throws -> MTLRenderPipelineState) rethrows -> MTLRenderPipelineState {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[name] { return cached }

        let state = try factory()
        cache[name] = state
        return state
    }

    func flush() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return cache.count
    }
}
