//
//  CompilationManager.swift
//  Typstwriter
//
//  Created by Ben Dixon on 5/15/26.
//

import SwiftUI
import Compiler
import PDFKit

@Observable
final class CompiledDocuments {
    fileprivate(set) var typst: [URL: Data] = [:]
    var pdf: [URL: PDFDocument] = [:]
    var image: [URL: [CGImage]] = [:]
    
    var time: [URL: String] = [:]
    
    func removeDocuments(_ urls: Set<URL>) {
        urls.forEach { typst.removeValue(forKey: $0) }
        urls.forEach { pdf.removeValue(forKey: $0) }
        urls.forEach { image.removeValue(forKey: $0) }
    }
}

extension EnvironmentValues {
    @Entry var compiledDocuments: CompiledDocuments = CompiledDocuments()
}

struct CompilationManager: View {
    var body: some View {
        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
    }
}

enum DocumentCompilationError: Error {
    case pdfDocumentCompilationError
    case typstDocumentCompilationError
}

func compilePDF(pdfURL: URL, compiledDocuments: CompiledDocuments) throws {
    if let doc = PDFDocument(url: pdfURL) {
        compiledDocuments.pdf[pdfURL] = doc
    } else {
        throw DocumentCompilationError.pdfDocumentCompilationError
    }
}

enum TypstCompileError: Error {
    case compileFailed(String)
    case badPDF
}

func compileTypst(typstTemplateURL: URL, compiledDocuments: CompiledDocuments) throws {
    let clock = ContinuousClock()
    
    let renderTime = clock.measure {
        let absPath = typstTemplateURL.path(percentEncoded: false)
        let r = absPath.withCString { tw_render_all_pages($0, 4.0) }
        
        defer { tw_free_render_all(r) }

        if let err = r.error { /* String(cString:) … */ return }

        let buf = UnsafeBufferPointer(start: r.pages, count: Int(r.page_count))
        let images: [CGImage] = buf.compactMap { page in
            let data = Data(bytes: page.pixels.data, count: Int(page.pixels.len)) // copies
            return makeCGImage(data: data, w: Int(page.width), h: Int(page.height))
        }
            
        
        print("Compiled \(images.count) images")
        
        compiledDocuments.image[typstTemplateURL] = images
    }
    
    let ms = Double(renderTime.components.seconds) * 1_000
           + Double(renderTime.components.attoseconds) / 1_000_000_000_000_000

    compiledDocuments.time[typstTemplateURL] = String(format: "%.2f milliseconds", ms)
    
    
//
//    absPath.withCString { pathPtr in
//        contents.withCString { textPtr in
//            tw_set_source(pathPtr, textPtr)
//        }
//    }

//    let result = absPath.withCString { tw_compile_pdf($0) }
//
//    if let errPtr = result.error {
//        let msg = String(cString: errPtr)
//        tw_free_string(errPtr)
//        throw TypstCompileError.compileFailed(msg)
//    }
//
//    defer { tw_free_buf(result.pdf) }
//    guard result.pdf.data != nil, result.pdf.len > 0 else {
//        throw TypstCompileError.badPDF
//    }
//
//    let data = Data(bytes: result.pdf.data, count: Int(result.pdf.len))
//    compiledDocuments.typst[typstTemplateURL] = data
//
//    guard let compiledPDF = PDFDocument(data: data) else {
//        throw TypstCompileError.badPDF
//    }
//    compiledDocuments.pdf[typstTemplateURL] = compiledPDF
}

func makeCGImage(data: Data, w: Int, h: Int) -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let info: CGBitmapInfo = [.byteOrder32Big,
                              CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)]
    let provider = CGDataProvider(data: data as CFData)!
    let cgImage = CGImage(
        width: w,
        height: h,
        bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: w * 4,
        space: cs, bitmapInfo: info,
        provider: provider, decode: nil,
        shouldInterpolate: false, intent: .defaultIntent)!
    
    return cgImage
}
