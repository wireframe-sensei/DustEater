#!/usr/bin/env swift
import Foundation

// Quick test of scanner performance
let homePath = NSHomeDirectory()

print("📊 Starting scan of: \(homePath)")
let startTime = DispatchTime.now()

// Simulate the async scan by running it synchronously for testing
let task = Task {
    let scanner = DiskScanner()
    return await scanner.scan(rootPath: homePath, onProgress: nil)
}

// Run synchronously (for testing only)
let node = try! task.value

let endTime = DispatchTime.now()
let elapsed = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000

print("📊 Scan completed in: \(String(format: "%.3f", elapsed))s")
print("📊 Items found: \(node.itemCount)")
print("📊 Total size: \(node.size) bytes")
