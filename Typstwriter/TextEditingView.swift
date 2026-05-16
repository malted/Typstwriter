//
//  TextEditingView.swift
//  Typstwriter
//
//  Created by Ben Dixon on 5/12/26.
//

import SwiftUI
import Compiler
import CodeEditSourceEditor
import CodeEditLanguages
import CodeEditTextView

// MARK: - Typst syntax highlighting

enum TypstHighlightKind: UInt8 {
    case comment = 0, punctuation, escape, strong, emph, link, raw,
         label, ref, heading, listMarker, listTerm,
         mathDelimiter, mathOperator, keyword, `operator`,
         number, string, function, interpolated, error
}

/// One-pass UTF-8-byte → UTF-16-unit offset map. tw_highlight returns byte
/// offsets; NSRange wants UTF-16 units.
private func makeUTF16Map(_ s: String) -> [Int] {
    var map = [Int]()
    map.reserveCapacity(s.utf8.count + 1)
    var utf16Index = 0
    for scalar in s.unicodeScalars {
        let utf8Len = String(scalar).utf8.count
        for _ in 0..<utf8Len { map.append(utf16Index) }
        utf16Index += scalar.utf16.count
    }
    map.append(utf16Index)
    return map
}

private func capture(for kind: TypstHighlightKind) -> CaptureName? {
    switch kind {
    case .comment:       return .comment
    case .punctuation:   return nil
    case .escape:        return .string
    case .strong:        return .keyword
    case .emph:          return .keyword
    case .link:          return .string
    case .raw:           return .string
    case .label:         return .property
    case .ref:           return .property
    case .heading:       return .type
    case .listMarker:    return .keyword
    case .listTerm:      return .property
    case .mathDelimiter: return .keyword
    case .mathOperator:  return .keyword
    case .keyword:       return .keyword
    case .operator:      return .keyword
    case .number:        return .number
    case .string:        return .string
    case .function:      return .function
    case .interpolated:  return .variable
    case .error:         return .variableBuiltin
    }
}

final class TypstHighlightProvider: HighlightProviding {
    func setUp(textView: TextView, codeLanguage: CodeLanguage) {}

    func applyEdit(
        textView: TextView,
        range: NSRange,
        delta: Int,
        completion: @escaping @MainActor (Result<IndexSet, Error>) -> Void
    ) {
        let full = NSRange(location: 0, length: textView.string.utf16.count)
        completion(.success(IndexSet(integersIn: Range(full)!)))
    }

    func queryHighlightsFor(
        textView: TextView,
        range: NSRange,
        completion: @escaping @MainActor (Result<[HighlightRange], Error>) -> Void
    ) {
        let source = textView.string
        let result = source.withCString { tw_highlight($0) }
        defer { tw_free_highlight(result) }

        let runs = UnsafeBufferPointer(start: result.runs, count: Int(result.count))
        let map = makeUTF16Map(source)
        guard !map.isEmpty else {
            completion(.success([]))
            return
        }

        var out: [HighlightRange] = []
        out.reserveCapacity(runs.count)
        for run in runs {
            guard let kind = TypstHighlightKind(rawValue: run.kind),
                  let cap = capture(for: kind) else { continue }
            let startByte = Int(run.start)
            let endByte = startByte + Int(run.len)
            guard endByte <= map.count - 1 else { continue }
            let loc = map[startByte]
            let len = map[endByte] - loc
            guard len > 0 else { continue }
            let r = NSRange(location: loc, length: len)
            guard r.intersection(range) != nil else { continue }
            out.append(HighlightRange(range: r, capture: cap))
        }
        completion(.success(out))
    }
}

// MARK: - Editor

/// Pushes external text changes (file switch, programmatic edits) into the
/// underlying NSTextView without going through the SwiftUI binding loop.
final class TextSetterCoordinator: TextViewCoordinator {
    weak var controller: TextViewController?

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
    }

    func setText(_ newText: String) {
        guard let controller, let tv = controller.textView else { return }
        let current = tv.string
        guard current != newText else { return }
        tv.replaceCharacters(
            in: NSRange(location: 0, length: (current as NSString).length),
            with: newText
        )
    }
}

struct TextEditingView: View {
    @Binding var selectedFiles: Set<URL>
    @Environment(\.compiledDocuments) private var compiledDocuments

    var body: some View {
        if let url = selectedFiles.first {
            FileEditor(url: url, compiledDocuments: compiledDocuments)
                .id(url)
        } else {
            Text("Select a typst file to edit it")
        }
    }
}

struct FileEditor: View {
    let url: URL
    let compiledDocuments: CompiledDocuments

    @State private var buffer: String

    init(url: URL, compiledDocuments: CompiledDocuments) {
        self.url = url
        self.compiledDocuments = compiledDocuments
        let initial = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        _buffer = State(initialValue: initial)
    }

    var body: some View {
        VStack {
            TypstEditor(text: $buffer)
                .onChange(of: buffer) { _, new in
                    do {
                        try Data(new.utf8).write(to: url)
                        let path = url.path(percentEncoded: false)
                        path.withCString { p in
                            new.withCString { t in tw_set_source(p, t) }
                        }
                        try compileTypst(typstTemplateURL: url, compiledDocuments: compiledDocuments)
                    } catch {
                        print(error)
                    }
                }

            if let t = compiledDocuments.time[url],
               let n = compiledDocuments.image[url]?.count {
                Text("Compiled \(n) page\(n == 1 ? "" : "s") in \(t)")
                    .font(.caption2)
            }
        }
    }
}

enum TypstEditorTheme {
    /// One Dark-inspired, calmer than the old palette.
    static let dark = EditorTheme(
        text:           .init(color: NSColor(srgbRed: 0.86, green: 0.87, blue: 0.90, alpha: 1)),
        insertionPoint: NSColor(srgbRed: 0.40, green: 0.70, blue: 1.00, alpha: 1),
        invisibles:     .init(color: NSColor(srgbRed: 0.30, green: 0.32, blue: 0.36, alpha: 1)),
        background:     NSColor(srgbRed: 0.13, green: 0.14, blue: 0.17, alpha: 1),
        lineHighlight:  NSColor(srgbRed: 0.16, green: 0.18, blue: 0.22, alpha: 1),
        selection:      NSColor(srgbRed: 0.20, green: 0.30, blue: 0.45, alpha: 1),
        keywords:       .init(color: NSColor(srgbRed: 0.78, green: 0.55, blue: 0.85, alpha: 1)), // purple
        commands:       .init(color: NSColor(srgbRed: 0.40, green: 0.72, blue: 0.95, alpha: 1)), // blue
        types:          .init(color: NSColor(srgbRed: 0.90, green: 0.74, blue: 0.42, alpha: 1)), // amber
        attributes:     .init(color: NSColor(srgbRed: 0.78, green: 0.65, blue: 0.96, alpha: 1)),
        variables:      .init(color: NSColor(srgbRed: 0.86, green: 0.87, blue: 0.90, alpha: 1)),
        values:         .init(color: NSColor(srgbRed: 0.92, green: 0.66, blue: 0.43, alpha: 1)),
        numbers:        .init(color: NSColor(srgbRed: 0.92, green: 0.66, blue: 0.43, alpha: 1)),
        strings:        .init(color: NSColor(srgbRed: 0.60, green: 0.84, blue: 0.60, alpha: 1)), // soft green
        characters:     .init(color: NSColor(srgbRed: 0.92, green: 0.66, blue: 0.43, alpha: 1)),
        comments:       .init(color: NSColor(srgbRed: 0.48, green: 0.52, blue: 0.58, alpha: 1))
    )

    /// Light theme inspired by GitHub / Xcode default.
    static let light = EditorTheme(
        text:           .init(color: NSColor(srgbRed: 0.13, green: 0.14, blue: 0.17, alpha: 1)),
        insertionPoint: NSColor(srgbRed: 0.10, green: 0.45, blue: 0.95, alpha: 1),
        invisibles:     .init(color: NSColor(srgbRed: 0.75, green: 0.76, blue: 0.79, alpha: 1)),
        background:     NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1),
        lineHighlight:  NSColor(srgbRed: 0.95, green: 0.96, blue: 0.98, alpha: 1),
        selection:      NSColor(srgbRed: 0.78, green: 0.86, blue: 1.00, alpha: 1),
        keywords:       .init(color: NSColor(srgbRed: 0.69, green: 0.13, blue: 0.55, alpha: 1)), // magenta
        commands:       .init(color: NSColor(srgbRed: 0.10, green: 0.35, blue: 0.85, alpha: 1)), // blue
        types:          .init(color: NSColor(srgbRed: 0.55, green: 0.38, blue: 0.10, alpha: 1)),
        attributes:     .init(color: NSColor(srgbRed: 0.46, green: 0.27, blue: 0.72, alpha: 1)),
        variables:      .init(color: NSColor(srgbRed: 0.13, green: 0.14, blue: 0.17, alpha: 1)),
        values:         .init(color: NSColor(srgbRed: 0.62, green: 0.36, blue: 0.05, alpha: 1)),
        numbers:        .init(color: NSColor(srgbRed: 0.62, green: 0.36, blue: 0.05, alpha: 1)),
        strings:        .init(color: NSColor(srgbRed: 0.16, green: 0.46, blue: 0.20, alpha: 1)),
        characters:     .init(color: NSColor(srgbRed: 0.62, green: 0.36, blue: 0.05, alpha: 1)),
        comments:       .init(color: NSColor(srgbRed: 0.45, green: 0.48, blue: 0.52, alpha: 1))
    )
}

struct TypstEditor: View {
    @Binding var text: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var setter = TextSetterCoordinator()
    @State private var highlightProvider = TypstHighlightProvider()
    @State private var editorState = SourceEditorState()
    private var theme: EditorTheme {
        colorScheme == .dark ? TypstEditorTheme.dark : TypstEditorTheme.light
    }
    private let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    var body: some View {
        SourceEditor(
            $text,
            language: .default,
            configuration: SourceEditorConfiguration(
                appearance: .init(theme: theme, font: font, wrapLines: true),
                behavior: .init(indentOption: .tab)
            ),
            state: $editorState,
            highlightProviders: [highlightProvider],
            coordinators: [setter]
        )
        .onChange(of: text) { _, new in
            setter.setText(new)
        }
    }
}
