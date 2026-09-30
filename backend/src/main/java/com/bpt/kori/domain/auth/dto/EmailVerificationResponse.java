package com.bpt.kori.domain.auth.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Schema(description = "이메일 인증 요청 응답 DTO")
public class EmailVerificationResponse {

    @Schema(description = "성공 여부", example = "true")
    private boolean success;

    @Schema(description = "안내 메시지", example = "인증번호가 발송되었습니다. (테스트 환경 콘솔 로그 확인)")
    private String message;
}
