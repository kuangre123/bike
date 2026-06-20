import SwiftUI
import CyclingDomain

/// 时间线里的单次运动行。
struct RideRowView: View {
    let ride: RideModel

    private var type: ActivityType { RideMapping.activityType(of: ride) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: Formatters.activityIcon(type))
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(Formatters.clockTime(ride.startDate))
                        .font(.headline)
                    Text(Formatters.activityLabel(type))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if ride.isAutoDetected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                            .accessibilityLabel("自动检测")
                    }
                }
                Text(Formatters.duration(ride.duration))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let meters = ride.distanceMeters {
                    Text(Formatters.distance(meters))
                        .font(.subheadline.weight(.medium))
                } else if let hr = Formatters.heartRate(ride.avgHeartRate) {
                    Text(hr)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.pink)
                } else {
                    Text("无路线")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text(Formatters.calories(ride.calories))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
