//
//  DocumentView.swift
//  Typstwriter
//
//  Created by Ben Dixon on 5/13/26.
//

import SwiftUI
import AppKit

struct DocumentView: View {
    @Binding var selectedFiles: Set<URL>
    @Binding var projectRoot: Set<URL>
    @Binding var fileTree: [String: FileListEntry]

    @Environment(\.compiledDocuments) private var compiledDocuments: CompiledDocuments

    var body: some View {
        Group {
            if let url = selectedFiles.first {
                switch url.pathExtension {
                case "pdf": pdfView(url)
                case "typ", "typst": imageView(url)
                default: Label("Unsupported file type", systemImage: "exclamationmark.triangle")
                }
            } else {
                Label("Select a document", systemImage: "document")
            }
        }
        .onChange(of: fileTree) { _, new in
            let newAll = allURLs(new)
            
//            compiledDocuments.removeDocuments(
//                Set(compiledDocuments.typst.keys).subtracting(newAll)
//            )
            
            do {
                for url in newAll {
                    print("compileTypst on \(url)")
                    try compileTypst(typstTemplateURL: url, compiledDocuments: compiledDocuments)
                }
            } catch {
                print(error)
            }
        }
//        .onChange(of: fileTree) { _, new in
//            let newAll = allURLs(new)
//            Set(pdfDocs.keys).subtracting(newAll).forEach({ pdfDocs.removeValue(forKey: $0) })
//            
//            for url in newAll {
//                guard url.pathExtension == "pdf" else { continue }
//                guard let doc = PDFDocument(url: url) else { print("Bad doc!"); continue }
//                
//                pdfDocs[url] = doc
//            }
//        }
    }

    @ViewBuilder
    func pdfView(_ url: URL) -> some View {
        if let doc = compiledDocuments.pdf[url] {
            PDFViewRepresentable(document: doc)
        } else {
            Label("Couldn't open PDF \(url)", systemImage: "exclamationmark.triangle")
        }
    }
    
    @ViewBuilder
    func imageView(_ url: URL) -> some View {
        if let images = compiledDocuments.image[url] {
            ZoomableImagesView(images: images)
                .toolbar {
                    Button("Export PDF") {
                        
                    }
                }
        } else {
            Label("Couldn't open PDF \(url)", systemImage: "exclamationmark.triangle")
        }
    }
    
    private func allURLs(_ tree: [String: FileListEntry]) -> [URL] {
        tree.values.flatMap { entry -> [URL] in
            [entry.url] + (entry.children.map(allURLs) ?? [])
        }
    }
}

/// Keeps the document view centered when it's smaller than the visible
/// scroll area (NSScrollView leaves it at the leading edge otherwise).
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return rect }
        if rect.width > doc.frame.width {
            rect.origin.x = (doc.frame.width - rect.width) / 2
        }
        if rect.height > doc.frame.height {
            rect.origin.y = (doc.frame.height - rect.height) / 2
        }
        return rect
    }
}

/// Renders a stack of CGImages in an NSScrollView with native pinch zoom and
/// trackpad/mouse-wheel scrolling. Preserves zoom + scroll position across
/// updates so editing the source doesn't reset the view.
struct ZoomableImagesView: NSViewRepresentable {
    let images: [CGImage]

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var didFitInitially = false
        /// Identity of the last image set we built, so we only rebuild when it
        /// actually changes (not on every SwiftUI update).
        var lastImageSignature: [ObjectIdentifier] = []
    }

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSScrollView()
        sv.contentView = CenteringClipView()
        sv.allowsMagnification = true
        sv.minMagnification = 0.1
        sv.maxMagnification = 4.0
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = true
        sv.autohidesScrollers = true
        sv.drawsBackground = false
        installStack(in: sv, context: context)
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        // Only rebuild if the images actually changed identity-wise.
        let sig = images.map { ObjectIdentifier($0) }
        guard sig != context.coordinator.lastImageSignature else { return }
        installStack(in: sv, context: context)
    }

    private func installStack(in sv: NSScrollView, context: Context) {
        // Save scroll position + magnification so we can restore them.
        let prevMag = sv.magnification
        let prevOrigin = sv.contentView.bounds.origin
        let hadDocument = sv.documentView != nil

        let stack = makeStack(images)
        sv.documentView = stack
        sv.layoutSubtreeIfNeeded()
        context.coordinator.lastImageSignature = images.map { ObjectIdentifier($0) }

        if hadDocument {
            sv.magnification = prevMag
            sv.contentView.scroll(to: prevOrigin)
            sv.reflectScrolledClipView(sv.contentView)
            return
        }

        // First-time appearance: fit page width to the viewport.
        DispatchQueue.main.async {
            fitToWidth(sv)
            context.coordinator.didFitInitially = true
        }
    }

    private func fitToWidth(_ sv: NSScrollView) {
        guard let doc = sv.documentView else { return }
        let viewportWidth = sv.contentView.bounds.width
        let contentWidth = doc.frame.width
        guard contentWidth > 0, viewportWidth > 0 else { return }
        let target = max(sv.minMagnification, min(sv.maxMagnification, viewportWidth / contentWidth))
        sv.magnification = target
        sv.contentView.scroll(to: .zero)
        sv.reflectScrolledClipView(sv.contentView)
    }

    private func makeStack(_ images: [CGImage]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false

        for cg in images {
            let pointSize = NSSize(width: cg.width / 2, height: cg.height / 2)
            let img = NSImage(cgImage: cg, size: pointSize)
            let iv = NSImageView()
            iv.image = img
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                iv.widthAnchor.constraint(equalToConstant: pointSize.width),
                iv.heightAnchor.constraint(equalToConstant: pointSize.height),
            ])
            stack.addArrangedSubview(iv)
        }
        return stack
    }
}
