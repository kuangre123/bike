import XCTest
@testable import CyclingDomain

final class GPXExportTests: XCTestCase {
    private func sample(lat: Double, lon: Double, alt: Double?, t: TimeInterval) -> GPSSample {
        GPSSample(timestamp: Date(timeIntervalSince1970: t), latitude: lat, longitude: lon, speedMps: 5, altitude: alt)
    }

    func test_wellFormedHeaderAndTrack() {
        let gpx = gpxDocument(trackName: "晨骑", points: [
            sample(lat: 31.230416, lon: 121.473701, alt: 12.3, t: 0),
            sample(lat: 31.231000, lon: 121.474000, alt: 15.0, t: 60),
        ])
        XCTAssertTrue(gpx.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        XCTAssertTrue(gpx.contains("<gpx version=\"1.1\""))
        XCTAssertTrue(gpx.contains("<name>晨骑</name>"))
        XCTAssertTrue(gpx.contains("</gpx>"))
    }

    func test_trackpointCountAndCoords() {
        let gpx = gpxDocument(trackName: "t", points: [
            sample(lat: 31.230416, lon: 121.473701, alt: 12.3, t: 0),
            sample(lat: 31.231000, lon: 121.474000, alt: nil, t: 60),
        ])
        let count = gpx.components(separatedBy: "<trkpt ").count - 1
        XCTAssertEqual(count, 2)
        XCTAssertTrue(gpx.contains("lat=\"31.230416\""))
        XCTAssertTrue(gpx.contains("lon=\"121.473701\""))
    }

    func test_elevationOnlyWhenPresent() {
        let gpx = gpxDocument(trackName: "t", points: [
            sample(lat: 1, lon: 2, alt: 42.0, t: 0),
            sample(lat: 1, lon: 2, alt: nil, t: 1),
        ])
        XCTAssertEqual(gpx.components(separatedBy: "<ele>").count - 1, 1) // 只有第一个点有海拔
        XCTAssertTrue(gpx.contains("<ele>42.0</ele>"))
    }

    func test_timeIsISO8601UTC() {
        let gpx = gpxDocument(trackName: "t", points: [sample(lat: 1, lon: 2, alt: nil, t: 0)])
        XCTAssertTrue(gpx.contains("<time>1970-01-01T00:00:00Z</time>"))
    }

    func test_trackNameEscaped() {
        let gpx = gpxDocument(trackName: "A & B <x>", points: [])
        XCTAssertTrue(gpx.contains("<name>A &amp; B &lt;x&gt;</name>"))
        XCTAssertFalse(gpx.contains("A & B <x>"))
    }

    func test_emptyPointsStillValid() {
        let gpx = gpxDocument(trackName: "t", points: [])
        XCTAssertTrue(gpx.contains("<trkseg>"))
        XCTAssertTrue(gpx.contains("</trkseg>"))
        XCTAssertEqual(gpx.components(separatedBy: "<trkpt ").count - 1, 0)
    }
}
