import Foundation

/// Synthetic producer, no video/model/device. Uses the exact production candidate for its recorded outputs.
@main enum SyntheticCandidateCapture {
    static func main() throws {
        var rows: [[String:Any]]=[]
        var engine=TerminalObservationCandidate()
        func append(_ type:String,_ fields:[String:Any]) {
            var row=fields;row["schema"]="bpt.terminal-evidence.v1";row["type"]=type;row["sequence"]=rows.count;rows.append(row)
        }
        func encoded<T:Encodable>(_ value:T) throws->[String:Any] {
            try JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) as! [String:Any]
        }
        func event<T:Encodable>(_ type:String,_ value:T) throws {
            append(type,["payload":try encoded(value),"candidate_protocol":"bpt.terminal-candidate.v1"])
        }
        func flush() throws { for report in engine.drain() { try event("terminal_candidate_report",report) } }
        func emit(_ frame:TerminalObservationCandidate.Frame,_ degrees:Double) throws {
            try event("terminal_candidate_frame",frame);engine.observe(frame);try flush()
            var pose=[Double](repeating:0,count:51)
            for (s,e,w) in [(11,12,13),(14,15,16)] {
                pose[3*s]=1;pose[3*e]=0;pose[3*w]=cos(degrees * .pi/180);pose[3*w+1]=sin(degrees * .pi/180)
            }
            let kp=Array(repeating:[100.0,100.0,0.8],count:17).flatMap{$0}
            append("terminal_frame",["epoch":1,"frame":frame.frame,"source_index":frame.sourceIndex!,"source_pts":frame.sourceTime!,
                "source_time_value":Int64((frame.sourceTime!*1_000_000).rounded()),"source_time_scale":1_000_000,
                "source_kind":"camera_capture_index","time_basis":"sample_pts_seconds","size":[640,480],"rotation":0,
                "raw_2d":kp,"input_2d":kp,"assessment_2d":kp,"raw_3d":pose,"constrained_3d":pose,"adapted_3d":NSNull(),"assessment_3d":pose,
                "confidence_h36m":Array(repeating:0.8,count:17),"invalid":[Int](),"raw_state":"ok","assessment_state":"ok",
                "side":"left","side_view":true,"phase":frame.phase!,"active_rep_start":frame.activeRepStart as Any? ?? NSNull(),
                "filled":27,"row":21,"flush_tail":false,"unit_px":200,"judgement_up":[0,-1,0],
                "up_time_basis":"judgement_time_not_source_sensor","source_gravity_available":false])
        }
        append("terminal_header",["clock":"sample_pts_seconds","provenance":"synthetic_test","units_3d":"h36m17_xs_model_space_no_metric_guarantee",
            "units_2d":"analysis_image_pixels","configuration_location":"terminal_start","candidate_protocol":"bpt.terminal-candidate.v1"])
        append("terminal_start",["epoch":1,"exercise":"pushup","time_basis":"sample_pts_seconds","raw_source":"xs_output_before_constraints","lookahead":5,"cadence":1])
        try event("terminal_candidate_config",engine.config);engine.start(epoch:1);append("terminal_candidate_start",["epoch":1])
        for rep in 1...4 {
            let end=rep*100+10
            let original=TerminalObservationCandidate.Original(epoch:1,exercise:"pushup",rep:rep,startFrame:end,endFrame:end,side:"left",threshold:10,originalMaxima:["elbow":130])
            try event("terminal_candidate_begin",TerminalObservationCandidate.Begin(original:original,hostTime:Double(rep)*2))
            engine.begin(original,hostTime:Double(rep)*2);try flush()
            append("terminal_rep",["epoch":1,"rep":rep,"start_frame":end,"end_frame":end,"side":"left"])
            let top=rep==4 ? 140.0 : 170.0
            for i in 0...8 {
                let degrees=i==0 ? 130 : top
                let input=TerminalObservationCandidate.Frame(epoch:1,frame:end+i,sourceIndex:end+i,
                    sourceTime:Double(rep)*2+Double(i)*0.05,hostTime:Double(rep)*2+Double(i)*0.05,
                    activeRepStart:i==8 ? end+8:nil,side:"left",phase:"top",required2D:true,sideView:true,state:"ok",flushed:false,
                    coordinateKey:"640/480/0/front",assessmentAngles:["elbow":degrees],rawAngles:["elbow":degrees])
                try emit(input,degrees)
            }
        }
        append("terminal_eof_flush",["epoch":1,"trigger":"video_eof_test_hook","processing_queue_drained":true])
        append("terminal_candidate_end",["epoch":1,"reason":"set_end","host_time":8.5]);engine.end(epoch:1,reason:"set_end",hostTime:8.5);try flush()
        append("terminal_end",["epoch":1,"reason":"set_end","flush_complete":true,"incomplete":false])
        for row in rows { print(String(decoding:try JSONSerialization.data(withJSONObject:row,options:.sortedKeys),as:UTF8.self)) }
    }
}
