import Foundation
@main struct GeometryParity {
 static func main() throws {
  let input=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [[[Double]]]
  var output:[[String:Any]]=[]
  for (i,points) in input.enumerated() {
   let joints=points.map {SIMD3<Double>($0[0],$0[1],$0[2])}
   var engine=ExperimentalCoaching()
   let frame=ExperimentalCoaching.Frame(time:Double(i),exercise:"pushup",phase:"descending",state:"ok",raw:joints,corrected:joints,confidence:[Double](repeating:1,count:17),invalid:[],up:nil)
   let measured=engine.update(frame)
   var row:[String:Any]=measured.metrics.mapValues {$0.value as Any? ?? NSNull()}
   row["cameraTorsoSignedDeg"]=FormGeometry.signedTorsoAngle3D(joints,up:SIMD3(0,-1,0)) as Any? ?? NSNull()
   row["cameraHipLineDeviationRatio"]=FormGeometry.signedHipDeviation3D(joints,up:SIMD3(0,-1,0)) as Any? ?? NSNull()
   row["trunkInclineDeg"]=nil;output.append(row)
  }
  FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:output,options:[.sortedKeys]))
 }
}
