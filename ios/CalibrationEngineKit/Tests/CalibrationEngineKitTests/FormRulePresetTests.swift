import XCTest
@testable import CalibrationEngineKit

/// rules-calib: FormRulePreset == pose_feedback/rules/*.json (app_default.json == the Swift defaults), and judge() ==
/// the Python mirror pose_feedback/feedback/form_rules.py on tests/fixtures/form_rules_cases.json
/// (scripts/make_form_rules_fixture.py).
final class FormRulePresetTests: XCTestCase {
    struct RulesFile: Decodable {
        let name: String
        let values: [String: Double]
        let off: [String]
    }

    static var rulesDir: URL { MotionAGFormerLiveTests.root.appendingPathComponent("pose_feedback/rules") }

    static func rulesFiles() throws -> [RulesFile] {
        let urls = try FileManager.default.contentsOfDirectory(at: rulesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return try urls.map { try JSONDecoder().decode(RulesFile.self, from: Data(contentsOf: $0)) }
    }

    func testAppDefaultFileIsTheSwiftDefault() throws {
        let file = try XCTUnwrap(Self.rulesFiles().first { $0.name == "app_default" })
        for exercise in [FormExercise.pushUp, .squat, .barbellRow] {
            let tracker = FormWarningTracker(exercise: exercise)
            XCTAssertEqual(FormRulePreset.values(of: tracker), file.values, "\(exercise)")
            XCTAssertEqual(tracker.common.disabledRules, [])
        }
        XCTAssertEqual(file.off, [])
    }

    func testEveryPresetEqualsItsFile() throws {
        let files = try Self.rulesFiles().filter { $0.name != "app_default" }
        XCTAssertEqual(Set(files.map(\.name)), Set(FormRulePreset.presets.keys))
        let known = Set(FormRulePreset.doubles.keys).union(FormRulePreset.optionals.keys)
        let ruleKeys = Set(FormWarningTracker.rules.values.flatMap { $0.map(\.key) })
        for file in files {
            let preset = try XCTUnwrap(FormRulePreset.presets[file.name])
            XCTAssertEqual(preset.values, file.values, file.name)
            XCTAssertEqual(preset.off, Set(file.off), file.name)
            XCTAssertEqual(Set(file.values.keys).subtracting(known), [], "\(file.name): unknown fields")
            XCTAssertEqual(Set(file.off).subtracting(ruleKeys), [], "\(file.name): unknown rule keys")
        }
    }

    func testNoPresetMeansNoRulesCalibRule() {
        XCTAssertFalse(FormRulePreset.apply("no_such_preset", to: FormWarningTracker(exercise: .squat)))
        for exercise in [FormExercise.pushUp, .squat, .barbellRow] {
            let values = FormRulePreset.values(of: FormWarningTracker(exercise: exercise))
            XCTAssertEqual(Set(values.keys).intersection(FormRulePreset.optionals.keys), [], "rules-calib thresholds unset")
        }
        // Never delivered, joint known (worstJoint ignores keys that are not enabled).
        let tracker = FormWarningTracker(exercise: .barbellRow)
        XCTAssertTrue(tracker.common.enabledFeedbackKeys.isDisjoint(with: FormWarningTracker.rulesCalibKeys))
        XCTAssertTrue(FormWarningTracker.rulesCalibKeys.isSubset(of: FormWarningTracker.keysWithoutFlutterLines))
        XCTAssertTrue(FormWarningTracker.rulesCalibKeys.isSubset(of: Set(FeedbackJoint.byKey.keys)))
    }

    func testJudgeMatchesPython() throws {
        struct Case: Decodable {
            let exercise: String
            let preset: String
            let values: [String: Double]
            let off: [String]
            let reps: [[String: Double]]
            let fired: [[String]]
        }
        let url = MotionAGFormerLiveTests.root.appendingPathComponent("tests/fixtures/form_rules_cases.json")
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
        XCTAssertEqual(cases.count, 18)
        for (n, c) in cases.enumerated() {
            let tracker = FormWarningTracker(exercise: try XCTUnwrap(FormExercise(rawValue: c.exercise)))
            FormRulePreset.apply(.init(values: c.values, off: Set(c.off)), to: tracker)
            for (i, m) in c.reps.enumerated() {
                XCTAssertEqual(tracker.judge(m, history: Array(c.reps[..<i]), repIndex: i + 1), c.fired[i],
                               "case \(n) \(c.exercise) \(c.preset) rep \(i)")
            }
        }
    }
}
