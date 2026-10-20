import Foundation

@main
enum ExerciseMotionVerify {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fputs("usage: ExerciseMotionVerify tests/fixtures/exercise_motion_cases.json\n", stderr)
            exit(2)
        }
        let began = ProcessInfo.processInfo.systemUptime
        let result = try ExerciseMotionParity.verify(URL(fileURLWithPath: CommandLine.arguments[1]))
        let output: [String: Any] = [
            "checked": result.checked, "largest_numeric_error": result.largestError,
            "error_count": result.errors.count, "errors": Array(result.errors.prefix(20)),
            "elapsed_seconds": ProcessInfo.processInfo.systemUptime - began,
        ]
        let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8)!)
        exit(result.errors.isEmpty ? 0 : 1)
    }
}
