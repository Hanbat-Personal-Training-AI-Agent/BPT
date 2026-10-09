package com.bpt.kori.domain.report.controller;

import com.bpt.kori.domain.report.dto.ReportAnalysisResponseDto;
import com.bpt.kori.domain.report.service.ReportService;
import com.bpt.kori.security.UserPrincipal;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Tag(name = "Reports", description = "운동 리포트 및 통계 분석 API")
@RestController
@RequestMapping("/reports")
@RequiredArgsConstructor
public class ReportController {

    private final ReportService reportService;

    @Operation(
            summary = "리포트 분석 집계 조회",
            description = "지정된 기간(from~to) 동안 수행한 총 운동 세션 수, 종목별 세션 수(세션 많은 순), 자세 실수별 발생 횟수(횟수 많은 순)를 집계하여 반환합니다. 기간 파라미터가 없으면 전체 기록을 집계합니다."
    )
    @GetMapping("/analysis")
    public ResponseEntity<ReportAnalysisResponseDto> getReportAnalysis(
            @AuthenticationPrincipal UserPrincipal userPrincipal,
            @Parameter(description = "시작 날짜 (YYYY-MM-DD)", example = "2026-09-01")
            @RequestParam(value = "from", required = false) String from,
            @Parameter(description = "종료 날짜 (YYYY-MM-DD)", example = "2026-09-30")
            @RequestParam(value = "to", required = false) String to
    ) {
        ReportAnalysisResponseDto response = reportService.getReportAnalysis(userPrincipal.getUserId(), from, to);
        return ResponseEntity.ok(response);
    }
}
