import Foundation

/// 解析 BRouter 的 `voicehints`（请求带 `timode=3` 时返回）为转向指令。
///
/// 为什么要它而不是 `turnsFromPolyline`：几何推导把折线上每个 ≥20° 的拐角都当转弯，
/// 山路本身就是弯的——实测一条 9.2 km 山路，几何推导出 165 次播报，
/// 而 BRouter 给 27 次，因为它只在真正的路口决策处发提示。
/// 它还能给出「靠左/靠右」和「环岛第几个出口」，这些从几何上根本看不出来。
///
/// 每行格式（用真实响应核过）：`[坐标下标, 命令码, 环岛出口, 到下一条的距离, 转角]`。
/// 命令码：1 直行 · 2 左转 · 3 稍左 · 4 急左 · 5 右转 · 6 稍右 · 7 急右 ·
/// 8 靠左 · 9 靠右 · 10/11 掉头 · 12 偏航标记 · 13/14 环岛 · 15 直线段。
///
/// 末尾追加 `.arrive`、距离按折线自己算——和 `turnsFromPolyline` 的输出形状一致，
/// `navigationProgress` 不用改就能用。
public func parseBRouterVoiceHints(_ raw: Any?, coordinates: [GeoCoordinate]) -> [TurnInstruction] {
    guard coordinates.count >= 2 else { return [] }

    struct Hint { let index: Int; let direction: TurnDirection; let exit: Int? }
    var hints: [Hint] = []
    for row in (raw as? [[Any]]) ?? [] {
        guard row.count >= 2,
              let index = doubleValue(row[0]).map(Int.init),
              let command = doubleValue(row[1]).map(Int.init),
              index >= 0, index < coordinates.count - 1,   // 最后一个点留给 .arrive
              let direction = turnDirection(forBRouterCommand: command)
        else { continue }
        let exit = direction == .roundabout && row.count >= 3
            ? doubleValue(row[2]).map(Int.init) : nil
        hints.append(Hint(index: index, direction: direction, exit: exit))
    }
    hints.sort { $0.index < $1.index }

    // 距离不信任响应里那一列（语义是「到下一条」还是「距上一条」不值得赌），
    // 直接沿折线量两个下标之间的长度。
    var turns: [TurnInstruction] = []
    var previousIndex = 0
    for hint in hints {
        turns.append(TurnInstruction(
            coordinateIndex: hint.index,
            direction: hint.direction,
            distanceFromPreviousMeters: polylineLengthMeters(Array(coordinates[previousIndex...hint.index])),
            roundaboutExit: hint.exit))
        previousIndex = hint.index
    }
    let last = coordinates.count - 1
    turns.append(TurnInstruction(
        coordinateIndex: last,
        direction: .arrive,
        distanceFromPreviousMeters: polylineLengthMeters(Array(coordinates[previousIndex...last]))))
    return turns
}

private func turnDirection(forBRouterCommand command: Int) -> TurnDirection? {
    switch command {
    case 1: return .straight
    case 2: return .left
    case 3: return .slightLeft
    case 4: return .sharpLeft
    case 5: return .right
    case 6: return .slightRight
    case 7: return .sharpRight
    case 8: return .keepLeft
    case 9: return .keepRight
    case 10, 11: return .uTurn
    case 13, 14: return .roundabout
    default: return nil   // 12 偏航标记、15 直线段、以及未来新增的码：都不是要念的转弯
    }
}

/// JSON 数字经 `JSONSerialization` 出来可能是 Double 也可能是 Int / NSNumber，统一收。
private func doubleValue(_ any: Any) -> Double? {
    switch any {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let n as NSNumber: return n.doubleValue
    default: return nil
    }
}
