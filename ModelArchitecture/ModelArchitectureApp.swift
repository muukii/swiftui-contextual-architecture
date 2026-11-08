//
//  ModelArchitectureApp.swift
//  ModelArchitecture
//
//  Created by Hiroshi Kimura on 2026/01/26.
//

import SwiftUI

@main
struct ModelArchitectureApp: App {
  /// One registry shared by this app's windows, not one Session per window.
  @State private var uiContext = AppUIContext()

  var body: some Scene {
    WindowGroup {
      AppRootView(uiContext: uiContext)
        .onOpenURL { url in
          uiContext.handle(url: url)
        }
    }
  }
}
