import XCTest
import EntityModel
@testable import FantasyTavernApp

final class ConflictDecisionTests: XCTestCase {
    private func entity(name: String = "A", body: String = "") -> Entity {
        Entity(id: EntityID("a"), type: .character, name: name, body: body)
    }

    func test_noChange_noConflict_silentReload() {
        let baseline = entity(body: "old")
        let newDisk = entity(body: "new")
        let drafts: ConflictDecision.Drafts = ("A", "old", [], [:])
        let decision = ConflictDecision.decide(baseline: baseline, newDisk: newDisk, drafts: drafts)
        XCTAssertEqual(decision, .silentReload)
    }

    func test_draftsMatchNewDisk_inSync() {
        let baseline = entity(body: "old")
        let newDisk = entity(body: "new")
        let drafts: ConflictDecision.Drafts = ("A", "new", [], [:])
        let decision = ConflictDecision.decide(baseline: baseline, newDisk: newDisk, drafts: drafts)
        XCTAssertEqual(decision, .inSync)
    }

    func test_draftsDifferFromBoth_conflict() {
        let baseline = entity(body: "old")
        let newDisk = entity(body: "new")
        let drafts: ConflictDecision.Drafts = ("A", "mine", [], [:])
        let decision = ConflictDecision.decide(baseline: baseline, newDisk: newDisk, drafts: drafts)
        XCTAssertEqual(decision, .conflict)
    }

    func test_diskSameAsBaseline_andDraftsDiffer_inSyncDraftsKept() {
        // Disk did not change; user has local edits — no conflict, no reload.
        let baseline = entity(body: "old")
        let newDisk = entity(body: "old")
        let drafts: ConflictDecision.Drafts = ("A", "mine", [], [:])
        let decision = ConflictDecision.decide(baseline: baseline, newDisk: newDisk, drafts: drafts)
        XCTAssertEqual(decision, .inSync)
    }
}
