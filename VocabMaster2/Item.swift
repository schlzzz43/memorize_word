//
//  Item.swift
//  VocabMaster2
//
//  Created by 沈晨晖 on 2026/01/24.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
