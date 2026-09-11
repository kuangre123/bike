import XCTest
@testable import CyclingDomain

final class BRouterVoiceHintTests: XCTestCase {

    /// 正北方向等间距 10 个点，每段 100 m。
    private let coords: [GeoCoordinate] = (0..<10).map {
        GeoCoordinate(latitude: 39.9 + Double($0) * 100 / 111_320, longitude: 116.4)
    }

    /// 真实响应里的格式：[坐标下标, 命令, 出口, 到下一条的距离, 角度]
    private func hints(_ rows: [[Double]]) -> [TurnInstruction] {
        parseBRouterVoiceHints(rows, coordinates: coords)
    }

    // MARK: - 命令码映射（用真实响应核过：2 配 -89° 是左转，5 配 +85° 是右转）

    func testMapsCommandCodes() {
        let turns = hints([
            [1, 2, 0, 100, -89],   // 左转
            [2, 5, 0, 100, 85],    // 右转
            [3, 3, 0, 100, -42],   // 稍左
            [4, 6, 0, 100, 35],    // 稍右
            [5, 4, 0, 100, -127],  // 急左
            [6, 7, 0, 100, 130],   // 急右
            [7, 1, 0, 100, 6],     // 直行
        ])
        XCTAssertEqual(turns.dropLast().map(\.direction),
                       [.left, .right, .slightLeft, .slightRight, .sharpLeft, .sharpRight, .straight])
    }

    func testMapsKeepAndUTurn() {
        let turns = hints([[1, 8, 0, 100, -10], [2, 9, 0, 100, 10], [3, 10, 0, 100, 180], [4, 11, 0, 100, -180]])
        XCTAssertEqual(turns.dropLast().map(\.direction), [.keepLeft, .keepRight, .uTurn, .uTurn])
    }

    func testRoundaboutCarriesExitNumber() {
        let turns = hints([[2, 13, 3, 100, 90]])
        XCTAssertEqual(turns.first?.direction, .roundabout)
        XCTAssertEqual(turns.first?.roundaboutExit, 3)
    }

    /// 12 是偏航标记、15 是直线段，都不是转弯，不该念出来。
    func testSkipsNonTurnCommands() {
        let turns = hints([[1, 12, 0, 100, 0], [2, 15, 0, 100, 0], [3, 2, 0, 100, -90]])
        XCTAssertEqual(turns.dropLast().map(\.direction), [.left])
    }

    func testUnknownCommandIsSkippedNotCrashed() {
        let turns = hints([[1, 99, 0, 100, 0], [2, 2, 0, 100, -90]])
        XCTAssertEqual(turns.dropLast().count, 1)
    }

    // MARK: - 距离按折线算，不信任响应里那一列

    func testDistanceFromPreviousIsMeasuredAlongPolyline() {
        // 下标 2 和 5：距起点 200 m，两者相距 300 m
        let turns = hints([[2, 2, 0, 999, -90], [5, 5, 0, 999, 90]])
        XCTAssertEqual(turns[0].distanceFromPreviousMeters, 200, accuracy: 1)
        XCTAssertEqual(turns[1].distanceFromPreviousMeters, 300, accuracy: 1)
    }

    // MARK: - 和 turnsFromPolyline 行为对齐，navigationProgress 才能不加改动地用

    func testAppendsArriveAtLastCoordinate() {
        let turns = hints([[2, 2, 0, 100, -90]])
        XCTAssertEqual(turns.last?.direction, .arrive)
        XCTAssertEqual(turns.last?.coordinateIndex, coords.count - 1)
        XCTAssertEqual(turns.last?.distanceFromPreviousMeters ?? 0, 700, accuracy: 1)
    }

    func testEmptyHintsStillYieldArrive() {
        let turns = hints([])
        XCTAssertEqual(turns.map(\.direction), [.arrive])
    }

    // MARK: - 坏数据

    func testOutOfRangeIndexIsDropped() {
        let turns = hints([[50, 2, 0, 100, -90], [2, 5, 0, 100, 90]])
        XCTAssertEqual(turns.dropLast().map(\.coordinateIndex), [2])
    }

    func testUnsortedHintsAreSortedByIndex() {
        let turns = hints([[5, 5, 0, 100, 90], [2, 2, 0, 100, -90]])
        XCTAssertEqual(turns.dropLast().map(\.coordinateIndex), [2, 5])
    }

    func testGarbageInputYieldsOnlyArrive() {
        XCTAssertEqual(parseBRouterVoiceHints("nope", coordinates: coords).map(\.direction), [.arrive])
        XCTAssertEqual(parseBRouterVoiceHints(nil, coordinates: coords).map(\.direction), [.arrive])
    }

    func testTooFewCoordinatesYieldsNothing() {
        XCTAssertTrue(parseBRouterVoiceHints([[0, 2, 0, 1, -90]], coordinates: [coords[0]]).isEmpty)
    }
}
