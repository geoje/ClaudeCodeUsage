import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var usage: UsageMonitor

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(usage.sessionPercent).opacity(0.6)
                    Text(usage.weeklyPercent).opacity(0.6)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(usage.sessionReset)
                    Text(usage.weeklyReset)
                }.opacity(0.6)
            }

            Spacer().frame(width: 8)

            VStack(alignment: .leading, spacing: 0) {
                Text(usage.enterprisePercent)
                Text(usage.enterpriseReset).opacity(0.6)
            }

            Spacer().frame(width: 8)

            VStack(alignment: .leading, spacing: 0) {
                Text(usage.litellmPercent).opacity(0.6)
                Text(usage.litellmReset).opacity(0.6)
            }
        }
        .font(.system(size: 9, weight: .regular))
        .padding(.horizontal, 4)
        .monospacedDigit()
        .fixedSize()
    }
}

#Preview {
    let usage = UsageMonitor()
    usage.sessionPercent = "4%"
    usage.sessionReset = "3h"
    usage.weeklyPercent = "56%"
    usage.weeklyReset = "7d"
    usage.enterprisePercent = "2%"
    usage.enterpriseReset = "34d"
    usage.litellmPercent = "5%"
    usage.litellmReset = "6d"
    return MenuBarLabelView(usage: usage)
}
