import Testing
@testable import SpiralKit

@Suite("SpiralGeometry")
struct SpiralGeometryTests {

    let geo = SpiralGeometry(totalDays: 30, width: 500, height: 500)

    @Test("Center is at (250, 250) for 500×500 canvas")
    func testCenter() {
        #expect(geo.cx == 250)
        #expect(geo.cy == 250)
    }

    @Test("Hour 0 is at top of spiral (roughly 12 o'clock)")
    func testHour0AtTop() {
        let p = geo.point(day: 1, hour: 0)
        // Hour 0 at top means y < cy
        #expect(p.y < geo.cy, "Hour 0 should be above center")
        // And roughly centered horizontally
        #expect(abs(p.x - geo.cx) < 30, "Hour 0 should be near horizontal center")
    }

    @Test("Radius increases with day for Archimedean spiral")
    func testRadiusIncreasesArchimedean() {
        let r0 = geo.radius(turns: 0)
        let r5 = geo.radius(turns: 5)
        let r15 = geo.radius(turns: 15)
        #expect(r0 < r5)
        #expect(r5 < r15)
    }

    @Test("Logarithmic spiral radius increases exponentially")
    func testLogarithmicSpiral() {
        let logGeo = SpiralGeometry(totalDays: 30, width: 500, height: 500, spiralType: .logarithmic)
        let r0 = logGeo.radius(turns: 0)
        let r5 = logGeo.radius(turns: 5)
        let r10 = logGeo.radius(turns: 10)
        #expect(r0 < r5)
        #expect(r5 < r10)
        // Log spiral: each interval should grow proportionally
        let ratio1 = r5 / r0
        let ratio2 = r10 / r5
        #expect(abs(ratio1 - ratio2) < 0.1, "Log spiral should have consistent growth ratio")
    }

    @Test("Points for same hour on different days form a radial line")
    func testSameHourRadialAlignment() {
        // All points at hour 0 should be directly above center (x ≈ cx)
        for day in 1...5 {
            let p = geo.point(day: day, hour: 0)
            #expect(abs(p.x - geo.cx) < 5, "Hour 0 day \(day): x=\(p.x) should be near cx=\(geo.cx)")
        }
    }

    @Test("Normal vector is perpendicular to radial direction")
    func testNormalPerpendicular() {
        let p = geo.point(day: 5, hour: 6)
        let n = geo.normal(day: 5, hour: 6)
        // Radial direction: (p.x - cx, p.y - cy)
        let rx = p.x - geo.cx
        let ry = p.y - geo.cy
        // Dot product of radial and normal should be ~0
        let dot = rx * n.nx + ry * n.ny
        #expect(abs(dot) < 0.001, "Normal should be perpendicular to radial direction")
    }

    @Test("Spiral steps count is proportional to totalDays")
    func testSpiralStepsCount() {
        let steps = geo.spiralSteps(step: 0.1)
        // 30 days / 0.1 step ≈ 300 steps
        #expect(steps.count > 280 && steps.count < 320)
    }

    @Test("Hour labels are generated for 0h multiples of 3")
    func testHourLabels() {
        let labels = geo.hourLabels()
        #expect(!labels.isEmpty)
        for label in labels {
            #expect(label.label.hasSuffix(":00"))
        }
    }

    @Test("Day rings count equals totalDays + 1")
    func testDayRingsCount() {
        let rings = geo.dayRings()
        #expect(rings.count == geo.totalDays + 1)
    }
}
