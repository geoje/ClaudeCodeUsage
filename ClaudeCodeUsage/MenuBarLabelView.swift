import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var usage: UsageMonitor

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(usage.sessionPercent)
                    Text(usage.weeklyPercent)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(usage.sessionReset)
                    Text(usage.weeklyReset)
                }
            }
            .opacity(usage.activeProfile == .home ? 1 : 0.6)

            Spacer().frame(width: 8)

            VStack(alignment: .leading, spacing: 0) {
                Text(usage.workPercent)
                Text(usage.workReset)
            }
            .opacity(usage.activeProfile == .work ? 1 : 0.6)
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
    usage.workPercent = "2%"
    usage.workReset = "34d"
    return MenuBarLabelView(usage: usage)
}
