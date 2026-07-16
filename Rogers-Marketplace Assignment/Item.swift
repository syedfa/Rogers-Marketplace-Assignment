//
//  Item.swift
//  Rogers-Marketplace Assignment
//
//  Created by Fayyazuddin  Syed on 2026-07-16.
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
