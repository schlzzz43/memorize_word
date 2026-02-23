//
//  SafariView.swift
//  VocabMaster2
//
//  Created on 2026/02/11.
//

import SwiftUI
import SafariServices

/// UIViewControllerRepresentable wrapper for SFSafariViewController
/// Allows opening web pages in an in-app browser without leaving the app
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        return SFSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // No updates needed
    }
}
