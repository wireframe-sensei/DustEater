import Foundation

enum DeveloperToolFolders {
    static let knownNames: Set<String> = [
        "homebrew", "npm", "pnpm", "yarn", "bun",
        "pip", "conda", "conda-anaconda-tos", "virtualenv",
        "go", "go-build", "node-gyp", "deno",
        "cargo", "rustup", "gem", "bundler", "cocoapods",
        "org.swift.swiftpm", "ms-playwright", "ms-playwright-go", "typescript",
        "checkpoint-nodejs", "claude-cli-nodejs", "update-informer-rs",
    ]

    static func isDeveloperTool(_ name: String) -> Bool {
        knownNames.contains(name.lowercased())
    }
}
