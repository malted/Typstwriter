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
    
    var pdfView = PDFView()
    
    var body: some View {
        NavigationSplitView {
            Text("ffi: \(add(3, 4))")
            FileListView(selections: $selectedFiles, projectRoot: $projectRoot, fileTree: $fileTree)
        } content: {
            DocumentView(selectedFiles: $selectedFiles, projectRoot: $projectRoot, fileTree: $fileTree)
        } detail: {
            Text("two")
        }
    }
}

//#Preview {
//    ContentView()
//}
