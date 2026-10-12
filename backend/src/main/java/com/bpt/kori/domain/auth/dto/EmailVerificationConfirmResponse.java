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
@Schema(description = "이메일 인증 확인 응답 DTO")
public class EmailVerificationConfirmResponse {

    @Schema(description = "인증 완료 여부", example = "true")
    private boolean verified;

    @Schema(description = "성공 여부 (호환용)", example = "true")
    private boolean success;

    @Schema(description = "안내 메시지", example = "이메일 인증이 완료되었습니다.")
    private String message;

    @Schema(description = "계정 찾기/비밀번호 재설정용 일회용 인증 토큰 (10분 유효)", example = "vt_abc123")
    private String verificationToken;
}
