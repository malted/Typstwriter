//
//  TextEditingView.swift
//  Typstwriter
//
//  Created by Ben Dixon on 5/12/26.
//

import SwiftUI

struct TextEditingView: View {
    @State private var fullText: String = "This is some editable text..."


    var body: some View {
        TextEditor(text: $fullText)
    }
}
