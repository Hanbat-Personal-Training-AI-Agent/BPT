import Foundation
import CryptoKit

/// Compile with the exact production candidate module. Invoke through replay_candidate.py for strict input validation.
@main enum TerminalCandidateReplay {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("expected one strict-validated numeric capture") }
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        var engine: TerminalObservationCandidate?
        var generated: [TerminalObservationCandidate.Report] = []
        var expected: [[String: Any]] = []
        var sawConfig = false
        let decoder = JSONDecoder()
        func decode<T: Decodable>(_ type: T.Type, _ value: Any) throws -> T {
            try decoder.decode(type, from: JSONSerialization.data(withJSONObject: value))
        }
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let row = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  row["schema"] as? String == "bpt.terminal-evidence.v1", let type = row["type"] as? String else { throw CocoaError(.fileReadCorruptFile) }
            switch type {
            case "terminal_candidate_config":
                let config = try decode(TerminalObservationCandidate.Config.self, row["payload"]!)
                guard config.valid, engine?.pendingRep == nil else { throw CocoaError(.fileReadCorruptFile) }
                engine = TerminalObservationCandidate(config: config);sawConfig=true
            case "terminal_candidate_start":
                guard engine != nil else { throw CocoaError(.fileReadCorruptFile) }
                engine!.start(epoch: row["epoch"] as! Int)
            case "terminal_candidate_begin":
                let input = try decode(TerminalObservationCandidate.Begin.self,row["payload"]!)
                engine?.begin(input.original,hostTime:input.hostTime)
            case "terminal_candidate_frame":
                engine?.observe(try decode(TerminalObservationCandidate.Frame.self,row["payload"]!))
            case "terminal_candidate_tick":
                engine?.expire(epoch:row["epoch"] as! Int,rep:row["rep"] as! Int,hostTime:row["host_time"] as! Double)
            case "terminal_candidate_end":
                engine?.end(epoch:row["epoch"] as! Int,reason:row["reason"] as! String,hostTime:row["host_time"] as? Double)
            case "terminal_candidate_report":
                expected.append(row["payload"] as! [String:Any])
            default: break
            }
            if engine != nil { generated += engine!.drain() }
        }
        guard sawConfig, engine?.pendingRep == nil, generated.count == expected.count else { throw CocoaError(.fileReadCorruptFile) }
        var assessments: [String:Int] = [:],coverage: [String:Int] = [:],closures:[String:Int] = [:]
        var stableSeconds: [Double] = []
        for (report,wanted) in zip(generated,expected) {
            let actual = try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as! [String:Any]
            guard NSDictionary(dictionary:actual).isEqual(to:wanted) else { throw CocoaError(.fileReadCorruptFile) }
            assessments[report.assessment,default:0]+=1;coverage[report.coverage,default:0]+=1;closures[report.closure,default:0]+=1
            stableSeconds.append(report.stableSeconds)
        }
        let result: [String:Any] = ["protocol":"bpt.terminal-candidate.v1","input_sha256":SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined(),
            "replayed_reports":generated.count,"exact_logged_report_parity":true,"assessment_counts":assessments,"coverage_counts":coverage,"closure_counts":closures,
            "maximum_observed_stability_seconds":stableSeconds.max() ?? 0,
            "interpretation":"Opt-in same-code causal candidate replay. Stable plateau is not full extension/correct form. Coverage, including timeout, depends on both source observations and captured operational watchdog timing. Original native reports/defaults unchanged."]
        print(String(decoding:try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
    }
}
