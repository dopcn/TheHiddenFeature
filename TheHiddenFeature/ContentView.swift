//
//  ContentView.swift
//  TheHiddenFeature
//
//  Created by FengWeizhou on 2026/7/30.
//

import SwiftUI

struct ContentView: View {
    @State private var model = AppSessionModel()

    var body: some View {
        Group {
            switch model.screen {
            case .featureSelection:
                FeatureSelectionView { experience in
                    model.selectExperience(experience)
                }
            case .pairing:
                PairingView(model: model)
            case .desktop:
                DesktopView(model: model.desktop)
            case .chat:
                ChatView(model: model.chat)
            }
        }
        .preferredColorScheme(model.screen == .chat ? .light : .dark)
        .alert(
            "连接提示",
            isPresented: Binding(
                get: { model.connection.errorMessage != nil },
                set: { if !$0 { model.connection.clearError() } }
            )
        ) {
            Button("好", role: .cancel) {
                model.connection.clearError()
            }
        } message: {
            Text(model.connection.errorMessage ?? "")
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didEnterBackgroundNotification
            )
        ) { _ in
            model.handleDidEnterBackground()
        }
    }
}

#Preview {
    ContentView()
}
