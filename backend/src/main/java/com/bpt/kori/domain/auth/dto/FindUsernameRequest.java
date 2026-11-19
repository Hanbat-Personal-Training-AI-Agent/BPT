package com.bpt.kori.domain.auth.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Getter
@Setter
@NoArgsConstructor
@Schema(description = "아이디 찾기 요청 DTO")
public class FindUsernameRequest {

    @Schema(description = "이메일 인증 확인 후 발급받은 일회용 인증 토큰", example = "vt_abc123")
    private String verificationToken;
}
