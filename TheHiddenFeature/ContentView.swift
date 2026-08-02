//
//  ContentView.swift
//  TheHiddenFeature
//
//  Created by FengWeizhou on 2026/7/30.
//

import SwiftUI

struct ContentView: View {
    @State private var model = DesktopSessionModel()

    var body: some View {
        Group {
            if model.phase == .desktop {
                DesktopView(model: model)
            } else {
                PairingView(model: model)
            }
        }
        .preferredColorScheme(.dark)
        .alert(
            "连接提示",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didEnterBackgroundNotification
            )
        ) { _ in
            if model.phase != .roleSelection {
                model.returnToRoleSelection()
            }
        }
    }
}

#Preview {
    ContentView()
}
