//
//  PDFPreviewView.swift
//  ShutterManager
//
//  Shows a PDF the app has just made (a report, a sheet of labels), with a button to share or
//  print it.
//

import SwiftUI
import PDFKit

/// A made PDF on screen, with sharing in the toolbar. Push it onto a navigation stack.
struct PDFPreviewView: View {
    let url: URL
    let title: String

    var body: some View {
        PDFDocumentView(url: url)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: url) {
                        Label("Share or Print", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("sharePDFButton")
                }
            }
    }
}

/// PDFKit's viewer: continuous pages, scaled to the width.
private struct PDFDocumentView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        view.accessibilityIdentifier = "pdfPreview"
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
