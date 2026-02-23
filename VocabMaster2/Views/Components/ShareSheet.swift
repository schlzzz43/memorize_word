//
//  ShareSheet.swift
//  VocabMaster2
//
//  Created on 2026/02/18.
//

import SwiftUI
import UIKit

/// 系统分享Sheet - 包装UIActivityViewController
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}
