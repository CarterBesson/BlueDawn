//
//  Item.swift
//  BlueDawn
//
//  Created by Carter Besson on 9/3/25.
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
