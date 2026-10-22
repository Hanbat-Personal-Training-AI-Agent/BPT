// swift-tools-version: 5.9
import PackageDescription

// calib-rca: 체형 촬영 원인 분석(docs/results/calib_root_cause.md)용 재생 도구.
// 앱의 CalibrationFrameAnalyzer·CalibrationEngine 소스를 심볼릭 링크로 그대로 쓰고,
// 프레임마다 관절 17개 좌표·신뢰도, crop, 측정값, 안내를 CSV 한 줄로 남긴다.
// 버퍼 가설 시험용으로 입력 프레임을 돌리거나(--rotate), 좌우 반전(--hflip),
// 9:16로 채우기(--pad-aspect), 화각 넓히기(--zoom-out)를 할 수 있다.
//   lockf -k /tmp/bpt-heavy.lock nice -n 10 swift build -c release --package-path scripts/calib_rca
//   scripts/calib_rca/.build/release/calib-rca [옵션] <영상> <출력.csv>
let package = Package(
    name: "calib-rca",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "calib-rca", path: "Sources/calib-rca"),
    ]
)
