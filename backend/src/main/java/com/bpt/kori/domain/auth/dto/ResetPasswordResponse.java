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
@Schema(description = "비밀번호 재설정 응답 DTO")
public class ResetPasswordResponse {

    @Schema(description = "재설정 성공 여부", example = "true")
    private boolean success;

    @Schema(description = "결과 메시지", example = "비밀번호가 성공적으로 변경되었습니다.")
    private String message;
}
