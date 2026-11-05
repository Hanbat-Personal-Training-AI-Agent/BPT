import Foundation

@main struct CandidateReplay {
    static func main() throws {
        let experiment=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:Any]
        let sensitivities=experiment["sensitivity"] as! [[String:Any]]
        let variants=experiment["variants"] as! [String:String]
        let base=experiment["parameters"] as! [String:Any]
        let declaredAt=experiment["experimentDeclaredAt"] as! String
        var engines:[String:CoachingCandidateEngine]=[:]
        var configurations:[String:CoachingCandidateEngine.Configuration]=[:]
        while let line=readLine() {
            let input=try JSONSerialization.jsonObject(with:Data(line.utf8)) as! [String:Any]
            let row=input["row"] as! [String:Any],exercise=input["exercise"] as! String,capture=input["captureID"] as! String
            let frame=CoachingCandidateEngine.Frame.terminal(row,exercise:exercise,captureID:capture)
            var results:[String:Any]=[:],requests:[[String:Any]]=[]
            let settings:[[String:Any]]=[["id":"base","parameters":[:]]] + sensitivities
            for setting in settings {
                let settingID=setting["id"] as! String
                let modes=settingID=="base" ? ["assessment_checked","raw_only","assessment_only"]:["assessment_checked"]
                var byMode:[String:Any]=[:]
                for mode in modes {
                    let key=capture+"/"+exercise+"/"+settingID+"/"+mode
                    if configurations[key]==nil {
                        var overrides=base;overrides.merge(setting["parameters"] as! [String:Any],uniquingKeysWith:{$1})
                        let provenance=Dictionary(uniqueKeysWithValues:overrides.keys.map {($0,"declared offline engineering experiment "+(experiment["id"] as! String)+"/"+settingID)})
                        configurations[key]=try .init(experimentID:experiment["id"] as! String,source:experiment["source"] as! String,experimentDeclaredAt:declaredAt,evaluationMode:"offline_declared",variant:variants[exercise]!,overrides:overrides,provenance:provenance)
                    }
                    var engine=engines[key] ?? CoachingCandidateEngine()
                    let measured:CoachingCandidateEngine.Frame
                    if mode=="assessment_checked" { measured=frame }
                    else {
                        let geometry=mode=="raw_only" ? frame.raw3D:frame.assessment3D
                        measured = .init(source:frame.source,context:frame.context,raw3D:geometry,assessment3D:geometry,raw2D:frame.raw2D,confidence:frame.confidence,invalid:frame.invalid,state:frame.state,captureID:frame.captureID)
                    }
                    let result=try engine.update(measured,configuration:configurations[key]!,includeRequests:settingID=="base" && mode=="assessment_checked")
                    if let original=result["requests"] as? [[String:Any]] {requests=original}
                    byMode[mode]=try CoachingCandidateRuntime.compact(result)
                    engines[key]=engine
                }
                results[settingID]=byMode
            }
            let encoded=try JSONSerialization.data(withJSONObject:["source":frame.source,"results":results,"requests":requests],options:[.sortedKeys])
            FileHandle.standardOutput.write(encoded);FileHandle.standardOutput.write(Data([10]))
        }
    }
}
