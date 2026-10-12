package com.bpt.kori.domain.auth.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Getter
@Setter
@NoArgsConstructor
@Schema(description = "토큰 갱신 요청 DTO")
public class RefreshTokenRequest {

    @NotBlank(message = "리프레시 토큰(refreshToken)을 입력해 주세요.")
    @Schema(description = "발급받은 리프레시 토큰", example = "eyJhbGciOiJIUzI1NiIsIn...")
    private String refreshToken;
}
