//
//  FileListView.swift
//  Typstwriter
//
//  Created by Ben Dixon on 5/12/26.
//

import SwiftUI
internal import UniformTypeIdentifiers
import Foundation

struct FileListEntry: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var children: [String: FileListEntry]?

    var sortedChildren: [FileListEntry]? {
        guard let children, !children.isEmpty else { return nil }
        return children.values.sorted {
            $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
        }
    }
}

struct FileListView: View {
    @Binding var selections: Set<URL>
    @Binding var projectRoot: Set<URL>
    @Binding var fileTree: [String: FileListEntry]
    
    private var rootEntries: [FileListEntry] {
        fileTree.values.sorted {
            $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
        }
    }

    var body: some View {
        VStack {
            List(rootEntries, children: \.sortedChildren, selection: $selections) { item in
                VStack(alignment: .leading) {
                    Text(item.url.lastPathComponent)
                    Text(item.url.absoluteString)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .id(item.url)
            }
            .listStyle(.sidebar)
            .toolbar {
                Importer(projectRoot: $projectRoot, fileTree: $fileTree)
            }

            Text("\(selections.count) selected")
        }
    }
}

//#Preview {
//    FileListView()
//}

struct Importer: View {
    @Binding var projectRoot: Set<URL>
    @Binding var fileTree: [String: FileListEntry]
    
    @State private var isImporting = false
    
    let fileManager = FileManager.default
    
    var body: some View {
        Button("Choose project") {
            isImporting = true
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.plainText, .content, .folder],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            
            projectRoot = Set(urls)

            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { return }
                
                guard let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles],
                    errorHandler: { (url, error) -> Bool in
                        print("Failed to read \(url): \(error)")
                        return true
                    }
                ) else { return }
                
                for case let subURL as URL in enumerator {
                    do {
                        let resourceValues = try subURL.resourceValues(forKeys: [.isRegularFileKey])
                        if resourceValues.isRegularFile == true {
                            insertFileIntoTree(subURL, into: &fileTree, root: url)
                        }
                    } catch {
                        print("Error reading attributes: \(error)")
                    }
                }
                
//                url.stopAccessingSecurityScopedResource()
            }
        }
    }
    
    func insertFileIntoTree(_ fileURL: URL, into tree: inout [String: FileListEntry], root: URL) {
        let comps = fileURL.pathComponents
        let start = root.pathComponents.count
        guard comps.count > start else { return }

        func go(from i: Int, accURL: URL, into dict: inout [String: FileListEntry]) {
            let head = comps[i]
            let nextURL = accURL.appendingPathComponent(head)
            let isLeaf = (i == comps.count - 1)
            var entry = dict[head] ?? FileListEntry(url: nextURL, children: isLeaf ? nil : [:])
            if !isLeaf {
                if entry.children == nil { entry.children = [:] }
                go(from: i + 1, accURL: nextURL, into: &entry.children!)
            }
            dict[head] = entry
        }

        go(from: start, accURL: root, into: &tree)
    }
}
