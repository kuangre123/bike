import SwiftUI

/// 时间线里的单次骑行行。
struct RideRowView: View {
    let ride: RideModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bicycle")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(Formatters.clockTime(ride.startDate))
                    .font(.headline)
                Text(Formatters.duration(ride.duration))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatters.distance(ride.distanceMeters))
                    .font(.subheadline.weight(.medium))
                Text(Formatters.calories(ride.calories))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
