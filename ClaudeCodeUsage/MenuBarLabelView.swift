import SwiftUI

struct MenuBarLabelView: View {
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("4%").opacity(0.6)
                    Text("56%").opacity(0.6)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("3h")
                    Text("7d")
                }.opacity(0.6)
            }

            Spacer().frame(width: 8)

            VStack(alignment: .leading, spacing: 0) {
                Text("2%")
                Text("34d").opacity(0.6)
            }
            
            Spacer().frame(width: 8)

            VStack(alignment: .leading, spacing: 0) {
                Text("5%").opacity(0.6)
                Text("6d").opacity(0.6)
            }
        }
        .font(.system(size: 9, weight: .regular))
        .padding(.horizontal, 4)
        .monospacedDigit()
        .fixedSize()
    }
}

#Preview {
    MenuBarLabelView()
}
