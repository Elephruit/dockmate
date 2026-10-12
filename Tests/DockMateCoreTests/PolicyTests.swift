import XCTest
import CoreGraphics
@testable import DockMateCore

final class PolicyTests: XCTestCase {
    private func wheel() -> CGEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line,
                            wheelCount: 2, wheel1: 3, wheel2: -2, wheel3: 0)!
        event.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        return event
    }

    func testWheelReversesAllDeltaRepresentations() {
        let event = wheel()
        XCTAssertTrue(ScrollPolicy.shouldReverse(event))
        let fields: [CGEventField] = [.scrollWheelEventDeltaAxis1,
            .scrollWheelEventDeltaAxis2, .scrollWheelEventPointDeltaAxis1,
            .scrollWheelEventPointDeltaAxis2]
        let before = fields.map { event.getIntegerValueField($0) }
        let fixed = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        ScrollPolicy.reverse(event)
        XCTAssertEqual(fields.map { event.getIntegerValueField($0) }, before.map { -$0 })
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), -fixed)
        ScrollPolicy.reverse(event)
        XCTAssertEqual(fields.map { event.getIntegerValueField($0) }, before)
    }

    func testTrackpadMomentumAndSyntheticEventsArePreserved() {
        for field: CGEventField in [.scrollWheelEventIsContinuous,
            .scrollWheelEventScrollPhase, .scrollWheelEventMomentumPhase,
            .eventSourceUnixProcessID] {
            let event = wheel()
            event.setIntegerValueField(field, value: 1)
            XCTAssertFalse(ScrollPolicy.shouldReverse(event))
        }
    }

    func testOnlyDisplayCannotBeDisabledAndUnplugRestores() {
        XCTAssertFalse(DisplayPolicy.canTurnOff(hasBuiltIn: true, activeExternalCount: 0))
        XCTAssertFalse(DisplayPolicy.canTurnOff(hasBuiltIn: false, activeExternalCount: 1))
        XCTAssertTrue(DisplayPolicy.canTurnOff(hasBuiltIn: true, activeExternalCount: 1))
        XCTAssertTrue(DisplayPolicy.shouldRestore(disabledByApp: true, activeExternalCount: 0))
        XCTAssertFalse(DisplayPolicy.shouldRestore(disabledByApp: false, activeExternalCount: 0))
        XCTAssertFalse(DisplayPolicy.shouldRestore(disabledByApp: true, activeExternalCount: 1))
    }
}
