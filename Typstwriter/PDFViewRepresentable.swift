//
//  PDFViewRepresentable.swift
//  Typstwriter
//
//  Created by Ben Dixon on 5/13/26.
//

import SwiftUI
import PDFKit

struct PDFViewRepresentable: NSViewRepresentable {
    typealias NSViewType = PDFView
    
    let document: PDFDocument
    
    public init(document: PDFDocument) {
        self.document = document
    }
    
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        
        return view
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        guard nsView !== document else { return }
        nsView.document = document
    }
}
