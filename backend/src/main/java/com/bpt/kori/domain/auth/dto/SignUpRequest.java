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

    @NotBlank(message = "전화번호를 입력해 주세요.")
    @jakarta.validation.constraints.Pattern(
            regexp = "^\\d{3}-\\d{3,4}-\\d{4}$",
            message = "전화번호 형식(예: 010-1234-5678)을 올바르게 입력해 주세요."
    )
    private String phoneNumber;

    @NotBlank(message = "생년월일을 입력해 주세요.")
    @jakarta.validation.constraints.Pattern(
            regexp = "^\\d{4}-\\d{2}-\\d{2}$",
            message = "생년월일 형식(예: 1998-05-15)을 올바르게 입력해 주세요."
    )
    private String birthDate;

    @NotNull(message = "서비스 이용약관에 동의해 주세요.")
    @AssertTrue(message = "서비스 이용약관에 동의해 주세요.")
    private Boolean termsAgreed;
}
