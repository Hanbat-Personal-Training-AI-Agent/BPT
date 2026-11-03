import Foundation
import simd

func pose(_ value: Any?) -> [SIMD3<Double>]? {
    guard let v=value as? [NSNumber], v.count==51, v.allSatisfy({$0.doubleValue.isFinite}) else { return nil }
    return stride(from:0,to:51,by:3).map { SIMD3(v[$0].doubleValue,v[$0+1].doubleValue,v[$0+2].doubleValue) }
}
func write(_ row:[String:Any],to handle:FileHandle) throws {
    let bytes=try JSONSerialization.data(withJSONObject:row,options:.sortedKeys)
    try handle.write(contentsOf:bytes+Data([10]))
}
let groups=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [[String:Any]]
let destination=URL(fileURLWithPath:CommandLine.arguments[2])
try Data().write(to:destination,options:.withoutOverwriting)
let handle=try FileHandle(forWritingTo:destination)
defer { try? handle.close() }
for group in groups {
    let exercise=group["exercise"] as! String
    for variant in ExerciseMotionVariant.allCases {
        var observer=ExerciseMotionObserver(configuration:.init(exercise:exercise,variant:variant,profile:nil,fixedCameraAssertion:false))
        for row in group["frames"] as! [[String:Any]] {
            let base:[String:Any]=["exercise":exercise,"variant":variant.rawValue,"sequence":row["sequence"]!,"frame":row["frame"]!,"flush":row["flush_tail"]!]
            guard let raw=pose(row["raw_3d"]) else {
                observer.reset();try write(base.merging(["withheldReason":"saved_raw_3d_unavailable"]){_,new in new},to:handle);continue
            }
            guard let points=pose(row["input_2d"]),let size=row["size"] as? [Int],size.count==2,size[1]>0,
                  let unit=(row["unit_px"] as? NSNumber)?.doubleValue,unit.isFinite,unit>0,
                  let epoch=row["epoch"] as? Int,let frame=row["frame"] as? Int,
                  let rotation=row["rotation"] as? Int,let flush=row["flush_tail"] as? Bool,
                  let timeValue=row["source_time_value"] as? Int64,let timeScale=row["source_time_scale"] as? Int32,
                  let index=row["source_index"] as? Int,let pts=(row["source_pts"] as? NSNumber)?.doubleValue else {
                observer.reset();try write(base.merging(["withheldReason":"saved_source_or_coordinate_context_unavailable"]){_,new in new},to:handle);continue
            }
            let coco=points.map { PoseKeypoint(x:$0.x,y:$0.y,confidence:$0.z) }
            let screen=try PoseCoordinateTransforms.coco17ToH36M17(coco).map { SIMD3($0.x/Double(size[1]),$0.y/Double(size[1]),$0.confidence) }
            let source=ExerciseMotionObserver.Source(session:epoch,frame:frame,sourceIndex:index,pts:pts,timeValue:timeValue,timeScale:timeScale,rotation:rotation,width:size[0],height:size[1],isVideo:true)
            let out=observer.update(raw:raw,screen2D:screen,modelToImageScale:unit/Double(size[1]),source:source,flush:flush)
            for (a,b) in zip(raw,out.raw) { for j in 0..<3 { precondition(a[j].bitPattern==b[j].bitPattern,"raw changed") } }
            if let candidate=out.candidate {
                let diagnostics=out.details["estimator"] as? [String:Any] ?? [:]
                for j in (diagnostics["observation_passthrough"] as? [Int] ?? []) + (diagnostics["expired_prediction_fallback"] as? [Int] ?? []) {
                    for axis in 0..<3 { precondition(candidate[j][axis].bitPattern==raw[j][axis].bitPattern,"passthrough not exact") }
                }
            }
            try write(base.merging(["observation":out.dictionary]){_,new in new},to:handle)
        }
    }
}
