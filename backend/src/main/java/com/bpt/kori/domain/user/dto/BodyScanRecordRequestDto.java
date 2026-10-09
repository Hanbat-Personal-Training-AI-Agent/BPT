package com.bpt.kori.domain.user.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Getter
@Setter
@NoArgsConstructor
@Schema(description = "체형 측정 완료 기록 요청 DTO")
public class BodyScanRecordRequestDto {

    @Schema(description = "체형 측정 일자 (YYYY-MM-DD, 미지정 시 오늘 날짜)", example = "2026-10-09")
    private String scanDate;

    @Schema(description = "체형 분석 로컬 파일 경로 (선택)", example = "/var/mobile/Containers/Data/Application/scan_01.dat")
    private String bodyScanLocalPath;
}
