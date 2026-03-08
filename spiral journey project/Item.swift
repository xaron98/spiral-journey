//
//  Item.swift
//  spiral journey project
//
//  Created by Carlos Perea Gallego on 8/3/26.
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
