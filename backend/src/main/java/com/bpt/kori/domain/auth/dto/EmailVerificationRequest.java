package com.bpt.kori.domain.auth.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Schema(description = "이메일 인증번호 발송 요청 DTO")
public class EmailVerificationRequest {

    @NotBlank(message = "이메일을 입력해 주세요.")
    @Email(message = "올바른 이메일 형식을 입력해 주세요.")
    @Schema(description = "인증번호를 발송할 이메일", example = "user@example.com")
    private String email;

    @Schema(description = "인증 용도 (SIGN_UP, FIND_ACCOUNT, FIND_USERNAME, RESET_PASSWORD)", example = "RESET_PASSWORD")
    private String purpose;

    @Schema(description = "계정 아이디 (비밀번호 재설정 purpose=RESET_PASSWORD 요청 시 동일 계정 여부 검증용)", example = "kori123")
    private String username;
}
