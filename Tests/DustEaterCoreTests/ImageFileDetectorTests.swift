import Testing
@testable import DustEaterCore

struct ImageFileDetectorTests {
    @Test func isImageAcceptsCommonImageExtensions() {
        #expect(ImageFileDetector.isImage(atPath: "/tmp/photo.jpg"))
        #expect(ImageFileDetector.isImage(atPath: "/tmp/photo.jpeg"))
        #expect(ImageFileDetector.isImage(atPath: "/tmp/photo.png"))
        #expect(ImageFileDetector.isImage(atPath: "/tmp/photo.heic"))
        #expect(ImageFileDetector.isImage(atPath: "/tmp/photo.gif"))
        #expect(ImageFileDetector.isImage(atPath: "/tmp/photo.tiff"))
        #expect(ImageFileDetector.isImage(atPath: "/tmp/photo.webp"))
    }

    @Test func isImageIsCaseInsensitive() {
        #expect(ImageFileDetector.isImage(atPath: "/tmp/PHOTO.JPG"))
    }

    @Test func isImageRejectsNonImageExtensions() {
        #expect(!ImageFileDetector.isImage(atPath: "/tmp/notes.txt"))
        #expect(!ImageFileDetector.isImage(atPath: "/tmp/main.swift"))
        #expect(!ImageFileDetector.isImage(atPath: "/tmp/archive.zip"))
        #expect(!ImageFileDetector.isImage(atPath: "/tmp/document.pdf"))
    }

    @Test func isImageRejectsFilesWithNoExtension() {
        #expect(!ImageFileDetector.isImage(atPath: "/tmp/README"))
        #expect(!ImageFileDetector.isImage(atPath: "/tmp/"))
    }

    @Test func isImageRejectsUnknownExtension() {
        #expect(!ImageFileDetector.isImage(atPath: "/tmp/file.notarealext123"))
    }
}
