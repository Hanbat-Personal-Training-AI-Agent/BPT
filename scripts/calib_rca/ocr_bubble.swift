// 화면 녹화에서 코리 말풍선 첫 줄을 읽어 기기 판정의 시간표를 만든다(Vision 한국어 OCR).
// #64 이전 화면(말풍선이 아래)의 1206×2622 녹화 기준 자르기 영역:
//   ffmpeg -i <녹화.mp4> -vf "fps=10,crop=900:80:260:2040" <dir>/b_%04d.png
//   swift scripts/calib_rca/ocr_bubble.swift <dir> > bubble_ocr.tsv     # "<파일>\t<글자>" 한 줄씩
// 파일 번호 n → 시각 (n-1)/10 초.
import AppKit
import Foundation
import Vision

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".png") }.sorted()
for name in files {
    guard let image = NSImage(contentsOf: dir.appendingPathComponent(name)),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
    let request = VNRecognizeTextRequest()
    request.recognitionLanguages = ["ko-KR"]
    request.recognitionLevel = .accurate
    try VNImageRequestHandler(cgImage: cg).perform([request])
    print("\(name)\t" + (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " "))
}
