package com.bpt.kori.domain.user.controller;

import com.bpt.kori.domain.auth.dto.*;
import com.bpt.kori.domain.user.service.AuthService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@Tag(name = "Auth", description = "인증 / 인가 및 회원가입, 이메일 인증 API")
@RestController
@RequestMapping("/auth")
@RequiredArgsConstructor
public class AuthController {

    private final AuthService authService;

    @Operation(summary = "로그인", description = "이메일 또는 아이디와 비밀번호로 로그인하여 JWT 토큰을 발급받습니다.")
    @PostMapping("/login")
    public ResponseEntity<TokenResponse> login(@Valid @RequestBody LoginRequest request) {
        TokenResponse response = authService.login(request);
        return ResponseEntity.ok(response);
    }

    @Operation(summary = "회원가입", description = "아이디, 이메일, 비밀번호, 전화번호, 생년월일, 약관 동의를 받아 새 계정을 생성합니다.")
    @PostMapping("/signup")
    public ResponseEntity<TokenResponse> signUp(@Valid @RequestBody SignUpRequest request) {
        TokenResponse response = authService.signUp(request);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @Operation(summary = "아이디 중복 확인", description = "입력한 아이디의 사용 가능 여부를 조회합니다.")
    @GetMapping("/check-username")
    public ResponseEntity<CheckUsernameResponse> checkUsername(@RequestParam("username") String username) {
        CheckUsernameResponse response = authService.checkUsername(username);
        return ResponseEntity.ok(response);
    }

    @Operation(summary = "이메일 인증번호 발송 요청 (Mock)", description = "아이디/비밀번호 찾기용으로 이메일에 6자리 인증번호를 전송합니다. (테스트 환경에서는 서버 로그에 출력)")
    @PostMapping("/verify-email/request")
    public ResponseEntity<EmailVerificationResponse> requestEmailVerification(@Valid @RequestBody EmailVerificationRequest request) {
        EmailVerificationResponse response = authService.requestEmailVerification(request);
        return ResponseEntity.ok(response);
    }

    @Operation(summary = "이메일 인증번호 확인 (Mock)", description = "입력한 이메일과 인증코드를 검증합니다. (현재 테스트용으로 항상 true 반환)")
    @PostMapping("/verify-email/confirm")
    public ResponseEntity<EmailVerificationConfirmResponse> confirmEmailVerification(@Valid @RequestBody EmailVerificationConfirmRequest request) {
        EmailVerificationConfirmResponse response = authService.confirmEmailVerification(request);
        return ResponseEntity.ok(response);
    }
}

