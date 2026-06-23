import Foundation

public enum TurnDirection: String, Sendable, Equatable {
    case straight, slightLeft, left, sharpLeft, slightRight, right, sharpRight, uTurn, arrive
}

public struct TurnInstruction: Equatable, Sendable {
    public let coordinateIndex: Int
    public let direction: TurnDirection
    public let distanceFromPreviousMeters: Double
    public init(coordinateIndex: Int, direction: TurnDirection, distanceFromPreviousMeters: Double) {
        self.coordinateIndex = coordinateIndex
        self.direction = direction
        self.distanceFromPreviousMeters = distanceFromPreviousMeters
    }
}

/// 带符号转向角 → 方向（正=右，负=左）。
private func classify(_ signed: Double) -> TurnDirection {
    let a = abs(signed)
    let right = signed > 0
    switch a {
    case ..<20:  return .straight
    case ..<45:  return right ? .slightRight : .slightLeft
    case ..<120: return right ? .right : .left
    case ..<160: return right ? .sharpRight : .sharpLeft
    default:     return .uTurn
    }
}

/// 从折线顶点的航向变化检测转向。末尾追加 .arrive。
/// `distanceFromPreviousMeters`：距上一个转向/起点的沿线距离。
public func turnsFromPolyline(_ coords: [GeoCoordinate], minTurnAngle: Double = 20) -> [TurnInstruction] {
    guard coords.count >= 2 else { return [] }
    var turns: [TurnInstruction] = []
    var sinceLast = 0.0

    for i in 1..<coords.count {
        let segLen = haversineMeters(
            lat1: coords[i - 1].latitude, lon1: coords[i - 1].longitude,
            lat2: coords[i].latitude, lon2: coords[i].longitude)
        sinceLast += segLen

        if i < coords.count - 1 {
            let incoming = bearingDegrees(from: coords[i - 1], to: coords[i])
            let outgoing = bearingDegrees(from: coords[i], to: coords[i + 1])
            let signed = signedTurnDegrees(incoming: incoming, outgoing: outgoing)
            if abs(signed) >= minTurnAngle {
                turns.append(TurnInstruction(
                    coordinateIndex: i, direction: classify(signed),
                    distanceFromPreviousMeters: sinceLast))
                sinceLast = 0
            }
        }
    }
    turns.append(TurnInstruction(
        coordinateIndex: coords.count - 1, direction: .arrive,
        distanceFromPreviousMeters: sinceLast))
    return turns
}
