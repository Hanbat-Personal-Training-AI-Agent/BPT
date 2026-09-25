package com.bpt.kori.domain.auth.dto;

import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Getter
@Setter
@NoArgsConstructor
public class SignUpRequest {

    @NotBlank(message = "아이디를 입력해 주세요.")
    private String username;

    @NotBlank(message = "이메일을 입력해 주세요.")
    @Email(message = "올바른 이메일 형식을 입력해 주세요.")
    private String email;

    @NotBlank(message = "비밀번호를 입력해 주세요.")
    private String password;

    private String name;

    @NotNull(message = "서비스 이용약관에 동의해 주세요.")
    @AssertTrue(message = "서비스 이용약관에 동의해 주세요.")
    private Boolean termsAgreed;

    @NotNull(message = "개인정보 수집 및 이용에 동의해 주세요.")
    @AssertTrue(message = "개인정보 수집 및 이용에 동의해 주세요.")
    private Boolean privacyAgreed;
}
