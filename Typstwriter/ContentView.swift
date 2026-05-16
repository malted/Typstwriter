//
//  ContentView.swift
//  Typstwriter
//
//  Created by Ben Dixon on 5/12/26.
//

import SwiftUI
import Compiler
import PDFKit

struct ContentView: View {
    @State var projectRoot: Set<URL> = []
    @State var selectedFiles: Set<URL> = []
    @State var fileTree: [String: FileListEntry] = [:]
    @State private var compiledDocuments = CompiledDocuments()

    var pdfView = PDFView()

    var body: some View {
        NavigationSplitView {
            Text("ffi: \(add(3, 4))")
            FileListView(selections: $selectedFiles, projectRoot: $projectRoot, fileTree: $fileTree)
                .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 500)
        } content: {
            DocumentView(selectedFiles: $selectedFiles, projectRoot: $projectRoot, fileTree: $fileTree)
        } detail: {
            if let ext = selectedFiles.first?.pathExtension.lowercased(), ["typ", "typst"].contains(ext) {
                TextEditingView(selectedFiles: $selectedFiles)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 500)
            } else {
                Color.clear.navigationSplitViewColumnWidth(min: 0, ideal: 0, max: 0)
            }
        }
        .environment(\.compiledDocuments, compiledDocuments)
        .onReceive(NotificationCenter.default.publisher(for: .openProject)) { note in
            guard let url = note.userInfo?["url"] as? URL else { return }
            projectRoot = [url]
            fileTree = [:]
            selectedFiles = []
            loadProjectTree(rootURL: url, into: &fileTree)
        }
    }
}

//#Preview {
//    ContentView()
//}
