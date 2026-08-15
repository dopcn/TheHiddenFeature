import SwiftUI

struct ChatPlaceholderView: View {
    var body: some View {
        ZStack {
            Color(red: 0.93, green: 0.93, blue: 0.93)
                .ignoresSafeArea()
            ProgressView("正在准备对话…")
                .foregroundStyle(.black)
        }
    }
}
