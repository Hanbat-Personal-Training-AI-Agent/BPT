package com.bpt.kori.domain.auth.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Getter
@Setter
@NoArgsConstructor
@Schema(description = "비밀번호 재설정 요청 DTO")
public class ResetPasswordRequest {

    @Schema(description = "사용자 아이디", example = "jihoon_kim")
    private String username;

    @NotBlank(message = "이메일을 입력해 주세요.")
    @Schema(description = "가입 이메일", example = "jihoon@example.com")
    private String email;

    @Schema(description = "이메일 인증 확인 후 발급받은 일회용 인증 토큰", example = "vt_abc123")
    private String verificationToken;

    @NotBlank(message = "새 비밀번호를 입력해 주세요.")
    @Schema(description = "새 비밀번호 (6자 이상)", example = "newPassword123!")
    private String newPassword;

    @Schema(description = "이메일 인증 코드 (토큰 미사용 시 호환용)", example = "842109")
    private String code;
}
