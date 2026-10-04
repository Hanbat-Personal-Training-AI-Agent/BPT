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

    @Schema(description = "안내 메시지", example = "이메일 인증이 완료되었습니다.")
    private String message;
}
