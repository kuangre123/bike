import SwiftUI
import CyclingDomain

/// 时间线里的单次运动行。
struct RideRowView: View {
    let ride: RideModel

    private var type: ActivityType { RideMapping.activityType(of: ride) }
    private var source: RideSource { RideMapping.source(of: ride) }

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 6) {
                Image(systemName: Formatters.activityIcon(type))
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(Formatters.activityLabel(type))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(accentColor)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(Formatters.clockTime(ride.startDate))
                        .font(.headline.weight(.heavy))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if ride.isAutoDetected {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 6, height: 6)
                            .accessibilityLabel("自动检测")
                    }
                }
                Text(Formatters.duration(ride.duration))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text(primaryMetric)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(primaryMetricColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(Formatters.calories(ride.calories))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary.opacity(0.55))
        }
        .padding(14)
        .background(Color.white.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.85), lineWidth: 1)
        )
        .shadow(color: accentColor.opacity(0.11), radius: 12, y: 7)
    }

    private var primaryMetric: String {
        if let meters = ride.distanceMeters {
            let text = Formatters.distance(meters)
            return source == .motionOnly ? "估算 \(text)" : text
        }
        if let hr = Formatters.heartRate(ride.avgHeartRate) {
            return hr
        }
        return "无路线"
    }

    private var primaryMetricColor: Color {
        ride.distanceMeters == nil && ride.avgHeartRate != nil ? .pink : .primary
    }

    private var accentColor: Color {
        switch type {
        case .walking: return Color(red: 0.22, green: 0.70, blue: 0.38)
        case .running: return Color(red: 0.95, green: 0.48, blue: 0.18)
        case .cycling: return Color(red: 0.04, green: 0.62, blue: 0.82)
        case .other: return Color(red: 0.72, green: 0.36, blue: 0.86)
        }
    }

    private var gradientColors: [Color] {
        switch type {
        case .walking:
            return [Color(red: 0.38, green: 0.86, blue: 0.50), Color(red: 0.18, green: 0.66, blue: 0.46)]
        case .running:
            return [Color(red: 1.00, green: 0.70, blue: 0.22), Color(red: 0.95, green: 0.38, blue: 0.18)]
        case .cycling:
            return [Color(red: 0.08, green: 0.75, blue: 0.92), Color(red: 0.18, green: 0.78, blue: 0.62)]
        case .other:
            return [Color(red: 0.88, green: 0.48, blue: 0.86), Color(red: 0.58, green: 0.42, blue: 0.90)]
        }
    }
}
