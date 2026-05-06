//
//  FromInkApp.swift
//  FromInk
//
//  Created by Alex Blair on 5/1/26.
//

import SwiftUI
import SwiftData

@main
struct FromInkApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Item.self, RoutedItem.self, Notebook.self, Folder.self])
    }
}
