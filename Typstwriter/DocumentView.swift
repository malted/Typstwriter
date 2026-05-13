//
//  DocumentView.swift
//  Typstwriter
//
//  Created by Ben Dixon on 5/13/26.
//

import SwiftUI
import PDFKit
import Compiler

struct DocumentView: View {
    @Binding var selectedFiles: Set<URL>
    @Binding var projectRoot: Set<URL>
    @Binding var fileTree: [String: FileListEntry]
    
    @State private var typstData: [URL: Data] = [:]
    
    var body: some View {
        Group {
            if let url = selectedFiles.first {
                switch url.pathExtension {
                case "pdf": pdfView(url)
                case "typst": typstView(url)
                default: Label("Unsupported file type", systemImage: "exclamationmark.triangle")
                }
            } else {
                Label("Select a document", systemImage: "document")
            }
        }
        .onChange(of: fileTree) { _, new in
            let newAll = allURLs(new)
            Set(typstData.keys).subtracting(newAll).forEach({ typstData.removeValue(forKey: $0) })
            
            for url in newAll {
                let contents = try! String(contentsOf: url, encoding: .utf8)
                
                let buf = contents.withCString { compile_typst($0) }
                defer { free_buf(buf) }
                let data = Data(bytes: buf.data, count: Int(buf.len))
                
                typstData[url] = data
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
        if let doc = PDFDocument(url: url) {
            PDFViewRepresentable(document: doc)
        } else {
            Label("Couldn't open PDF", systemImage: "exclamationmark.triangle")
        }
    }
    
    @ViewBuilder
    func typstView(_ url: URL) -> some View {
        if let data = typstData[url], let doc = PDFDocument(data: data) {
            PDFViewRepresentable(document: doc)
        } else {
            Label("Couldn't open PDF", systemImage: "exclamationmark.triangle")
        }
    }
    
    private func allURLs(_ tree: [String: FileListEntry]) -> [URL] {
        tree.values.flatMap { entry -> [URL] in
            [entry.url] + (entry.children.map(allURLs) ?? [])
        }
    }
}

//#Preview {
//    DocumentView(selectedFiles: .constant(Set([URL(string: "file:///Users/malted/Desktop/Crash/report.pdf")!])))
//}
