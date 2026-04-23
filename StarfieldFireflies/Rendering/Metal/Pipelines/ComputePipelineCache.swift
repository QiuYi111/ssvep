//
//  ComputePipelineCache.swift
//  StarfieldFireflies
//
//  Thread-safe dictionary cache for MTLComputePipelineState objects.
//

import Metal
import Foundation

final class ComputePipelineCache {

    private var cache: [String: MTLComputePipelineState] = [:]
    private let lock = NSLock()

    func getOrCreate(name: String, factory: () throws -> MTLComputePipelineState) rethrows -> MTLComputePipelineState {
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
