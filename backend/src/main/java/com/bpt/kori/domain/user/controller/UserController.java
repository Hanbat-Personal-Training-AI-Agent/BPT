package com.bpt.kori.domain.user.controller;

import com.bpt.kori.domain.user.dto.DashboardSummaryResponseDto;
import com.bpt.kori.domain.user.dto.OnboardingRequest;
import com.bpt.kori.domain.user.dto.OnboardingResponse;
import com.bpt.kori.domain.user.dto.UserDto;
import com.bpt.kori.domain.user.dto.UserUpdateRequestDto;
import com.bpt.kori.domain.user.service.UserService;
import com.bpt.kori.security.UserPrincipal;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

@Tag(name = "Users", description = "사용자 프로필, 온보딩, 대시보드 API")
@RestController
@RequestMapping("/users")
@RequiredArgsConstructor
public class UserController {

    private final UserService userService;

    @Operation(summary = "내 프로필 조회", description = "현재 로그인된 사용자의 상세 프로필 정보를 반환합니다.")
    @GetMapping("/me")
    public ResponseEntity<UserDto> getMyProfile(@AuthenticationPrincipal UserPrincipal userPrincipal) {
        UserDto profile = userService.getProfile(userPrincipal.getUserId());
        return ResponseEntity.ok(profile);
    }

    @Operation(summary = "내 프로필 수정", description = "사용자의 아이디, 이메일, 이름, 성별, 키, 몸무게, 목표, 마지막 체형 측정일 등을 수정합니다.")
    @PutMapping("/me")
    public ResponseEntity<UserDto> updateMyProfile(
            @AuthenticationPrincipal UserPrincipal userPrincipal,
            @RequestBody UserUpdateRequestDto request
    ) {
        UserDto updated = userService.updateProfile(userPrincipal.getUserId(), request);
        return ResponseEntity.ok(updated);
    }

    @Operation(summary = "체형 측정 완료 기록 (API 13)", description = "체형 촬영(사진 4장) 완료 후 마지막 체형 측정일(lastBodyScanDate)을 오늘 날짜(또는 요청된 날짜)로 갱신합니다.")
    @PostMapping({"/me/body-scans", "/me/body-scan"})
    public ResponseEntity<UserDto> recordBodyScan(
            @AuthenticationPrincipal UserPrincipal userPrincipal,
            @RequestBody(required = false) com.bpt.kori.domain.user.dto.BodyScanRecordRequestDto request
    ) {
        UserDto updated = userService.recordBodyScan(userPrincipal.getUserId(), request);
        return ResponseEntity.ok(updated);
    }

    @Operation(summary = "온보딩 정보 등록 (API 6)", description = "성별, 키, 몸무게, 운동 목표, 주간 빈도, 알림 시간(예: '18:00')을 저장하고 오늘 날짜를 체형 스캔일(lastBodyScanDate)로 기록합니다.")
    @PutMapping("/me/onboarding")
    public ResponseEntity<OnboardingResponse> updateOnboarding(
            @AuthenticationPrincipal UserPrincipal userPrincipal,
            @RequestBody OnboardingRequest request
    ) {
        OnboardingResponse response = userService.updateOnboarding(userPrincipal.getUserId(), request);
        return ResponseEntity.ok(response);
    }

    @Operation(summary = "메인 홈 대시보드 요약 (API 12)", description = "주간 목표 달성률, 오늘 운동 시간(분), 세트수, 체형 재측정(30일 주기) 필요 여부 및 최근 운동 기록을 제공합니다.")
    @GetMapping("/me/dashboard")
    public ResponseEntity<DashboardSummaryResponseDto> getDashboardSummary(@AuthenticationPrincipal UserPrincipal userPrincipal) {
        DashboardSummaryResponseDto response = userService.getDashboardSummary(userPrincipal.getUserId());
        return ResponseEntity.ok(response);
    }
}
