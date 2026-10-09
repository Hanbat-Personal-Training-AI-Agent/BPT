package com.bpt.kori.domain.auth.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Getter
@Setter
@NoArgsConstructor
@Schema(description = "로그인 요청 DTO")
public class LoginRequest {

    @NotBlank(message = "아이디를 입력해 주세요.")
    @Schema(description = "사용자 아이디", example = "jihoon_kim")
    private String username;

    @NotBlank(message = "비밀번호를 입력해 주세요.")
    @Schema(description = "비밀번호", example = "password123!")
    private String password;

    public void setEmail(String email) {
        if (this.username == null || this.username.isBlank()) {
            this.username = email;
        }
    }
}
