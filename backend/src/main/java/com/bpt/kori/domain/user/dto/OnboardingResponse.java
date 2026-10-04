package com.bpt.kori.domain.user.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;

@Getter
@AllArgsConstructor
@Builder
@Schema(description = "온보딩 정보 등록 응답 DTO")
public class OnboardingResponse {

    @Schema(description = "사용자 고유 ID", example = "1")
    private final Long userId;

    @Schema(description = "온보딩 완료 여부", example = "true")
    private final Boolean isOnboardingCompleted;
}
