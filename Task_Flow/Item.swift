//
//  Item.swift
//  Task_Flow
//
//  Created by 黃浚銘 on 2026/3/12.
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
