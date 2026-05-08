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
    @AppStorage("appearanceSetting") private var appearance: AppearanceSetting = .system

    var body: some Scene {
        WindowGroup {
            ContentView()
                .designSystem(.standard)
                .preferredColorScheme(appearance.colorScheme)
        }
        .modelContainer(for: [Item.self, RoutedItem.self, Notebook.self, Folder.self])
    }
}
