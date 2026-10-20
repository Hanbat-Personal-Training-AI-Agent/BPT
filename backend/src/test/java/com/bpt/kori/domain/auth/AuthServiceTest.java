package com.bpt.kori.domain.auth;

import com.bpt.kori.common.exception.CustomException;
import com.bpt.kori.common.exception.ErrorCode;
import com.bpt.kori.domain.auth.dto.CheckUsernameResponse;
import com.bpt.kori.domain.auth.dto.SignUpRequest;
import com.bpt.kori.domain.auth.dto.TokenResponse;
import com.bpt.kori.domain.user.entity.User;
import com.bpt.kori.domain.user.repository.UserRepository;
import com.bpt.kori.domain.user.service.AuthService;
import com.bpt.kori.security.JwtTokenProvider;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.password.PasswordEncoder;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;

@ExtendWith(MockitoExtension.class)
class AuthServiceTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private PasswordEncoder passwordEncoder;

    @Mock
    private JwtTokenProvider tokenProvider;

    @Mock
    private com.bpt.kori.domain.user.service.EmailService emailService;

    @InjectMocks
    private AuthService authService;

    private SignUpRequest validSignUpRequest;

    @BeforeEach
    void setUp() {
        validSignUpRequest = new SignUpRequest();
        validSignUpRequest.setUsername("jihoon_kim");
        validSignUpRequest.setEmail("jihoon@bpt.app");
        validSignUpRequest.setPassword("password123!");
        validSignUpRequest.setName("지훈");
        validSignUpRequest.setPhoneNumber("010-1234-5678");
        validSignUpRequest.setBirthDate("1998-05-15");
        validSignUpRequest.setTermsAgreed(true);
    }

    @Test
    @DisplayName("[API 2] 약관 동의 포함 회원가입 성공")
    void signUp_success() {
        // given
        given(userRepository.existsByEmail("jihoon@bpt.app")).willReturn(false);
        given(userRepository.existsByUsername("jihoon_kim")).willReturn(false);
        given(passwordEncoder.encode(anyString())).willReturn("encodedPassword");
        given(userRepository.save(any(User.class))).willAnswer(invocation -> {
            User user = invocation.getArgument(0);
            return User.builder()
                    .id(1L)
                    .username(user.getUsername())
                    .email(user.getEmail())
                    .name(user.getName())
                    .termsAgreed(user.getTermsAgreed())
                    .build();
        });
        given(tokenProvider.generateAccessToken(any(), anyString(), anyString())).willReturn("mock.jwt.token");
        given(tokenProvider.generateRefreshToken(any())).willReturn("mock.refresh.token");
        given(tokenProvider.getAccessTokenExpirationSeconds()).willReturn(3600L);

        // when
        TokenResponse response = authService.signUp(validSignUpRequest);

        // then
        assertThat(response).isNotNull();
        assertThat(response.getToken()).isEqualTo("mock.jwt.token");
        assertThat(response.getTokenType()).isEqualTo("Bearer");
        verify(userRepository).save(any(User.class));
    }

    @Test
    @DisplayName("[API 2] 약관 미동의 시 TERMS_NOT_AGREED 예외 발생")
    void signUp_termsNotAgreed_throwsException() {
        // given
        validSignUpRequest.setTermsAgreed(false);

        // when & then
        assertThatThrownBy(() -> authService.signUp(validSignUpRequest))
                .isInstanceOf(CustomException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.TERMS_NOT_AGREED);
    }

    @Test
    @DisplayName("[API 1] 아이디 중복 확인")
    void checkUsername() {
        // given
        given(userRepository.existsByUsername("existing_user")).willReturn(true);
        given(userRepository.existsByUsername("new_user")).willReturn(false);

        // when
        CheckUsernameResponse taken = authService.checkUsername("existing_user");
        CheckUsernameResponse available = authService.checkUsername("new_user");

        // then
        assertThat(taken.isAvailable()).isFalse();
        assertThat(available.isAvailable()).isTrue();
    }

    @Test
    @DisplayName("아이디 전용 로그인 성공")
    void login_withUsername_success() {
        User user = User.builder()
                .id(1L)
                .username("jihoon_kim")
                .password("encodedPassword")
                .email("jihoon@bpt.app")
                .build();

        given(userRepository.findByUsername("jihoon_kim")).willReturn(java.util.Optional.of(user));
        given(passwordEncoder.matches("password123!", "encodedPassword")).willReturn(true);
        given(tokenProvider.generateAccessToken(1L, "jihoon_kim", "jihoon@bpt.app")).willReturn("mock.jwt.token");
        given(tokenProvider.generateRefreshToken(1L)).willReturn("mock.refresh.token");
        given(tokenProvider.getAccessTokenExpirationSeconds()).willReturn(3600L);

        com.bpt.kori.domain.auth.dto.LoginRequest loginReq = new com.bpt.kori.domain.auth.dto.LoginRequest();
        loginReq.setUsername("jihoon_kim");
        loginReq.setPassword("password123!");

        TokenResponse response = authService.login(loginReq);

        assertThat(response).isNotNull();
        assertThat(response.getToken()).isEqualTo("mock.jwt.token");
    }

    @Test
    @DisplayName("이메일 발송 및 인증 확인")
    void emailVerification_flow() {
        com.bpt.kori.domain.auth.dto.EmailVerificationRequest req = new com.bpt.kori.domain.auth.dto.EmailVerificationRequest();
        req.setEmail("test@bpt.app");

        var sendRes = authService.requestEmailVerification(req);
        assertThat(sendRes.isSuccess()).isTrue();

        // 1분 이내 재요청 시 RESEND_COOLDOWN_ACTIVE 예외 발생
        assertThatThrownBy(() -> authService.requestEmailVerification(req))
                .isInstanceOf(CustomException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.RESEND_COOLDOWN_ACTIVE);

        // 5회 오입력 시 번호 폐기 및 TOO_MANY_VERIFICATION_ATTEMPTS 예외
        com.bpt.kori.domain.auth.dto.EmailVerificationConfirmRequest confirmReq = new com.bpt.kori.domain.auth.dto.EmailVerificationConfirmRequest();
        confirmReq.setEmail("test@bpt.app");
        confirmReq.setCode("000000");

        for (int i = 0; i < 4; i++) {
            var res = authService.confirmEmailVerification(confirmReq);
            assertThat(res.isVerified()).isFalse();
        }

        assertThatThrownBy(() -> authService.confirmEmailVerification(confirmReq))
                .isInstanceOf(CustomException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.TOO_MANY_VERIFICATION_ATTEMPTS);
    }

    @Test
    @DisplayName("리프레시 토큰 갱신 성공")
    void refresh_token_success() {
        User user = User.builder()
                .id(1L)
                .username("jihoon_kim")
                .email("jihoon@bpt.app")
                .build();

        given(tokenProvider.validateToken("valid.refresh.token")).willReturn(true);
        given(tokenProvider.getUserIdFromToken("valid.refresh.token")).willReturn(1L);
        given(userRepository.findById(1L)).willReturn(java.util.Optional.of(user));
        given(tokenProvider.generateAccessToken(1L, "jihoon_kim", "jihoon@bpt.app")).willReturn("new.access.token");
        given(tokenProvider.generateRefreshToken(1L)).willReturn("new.refresh.token");
        given(tokenProvider.getAccessTokenExpirationSeconds()).willReturn(3600L);

        com.bpt.kori.domain.auth.dto.RefreshTokenRequest req = new com.bpt.kori.domain.auth.dto.RefreshTokenRequest();
        req.setRefreshToken("valid.refresh.token");

        TokenResponse response = authService.refresh(req);

        assertThat(response).isNotNull();
        assertThat(response.getAccessToken()).isEqualTo("new.access.token");
        assertThat(response.getRefreshToken()).isEqualTo("new.refresh.token");
    }

    @Test
    @DisplayName("비밀번호 재설정 인증번호 발송 요청 시 아이디와 이메일 일치하면 성공")
    void requestEmailVerification_resetPassword_success() {
        User user = User.builder()
                .id(1L)
                .username("jihoon_kim")
                .email("jihoon@bpt.app")
                .build();

        given(userRepository.findByUsername("jihoon_kim")).willReturn(java.util.Optional.of(user));

        var req = com.bpt.kori.domain.auth.dto.EmailVerificationRequest.builder()
                .email("jihoon@bpt.app")
                .purpose("RESET_PASSWORD")
                .username("jihoon_kim")
                .build();

        var res = authService.requestEmailVerification(req);
        assertThat(res.isSuccess()).isTrue();
    }

    @Test
    @DisplayName("비밀번호 재설정 인증번호 발송 요청 시 존재하지 않는 아이디면 USER_NOT_FOUND 예외 발생")
    void requestEmailVerification_resetPassword_userNotFound() {
        given(userRepository.findByUsername("unknown_user")).willReturn(java.util.Optional.empty());

        var req = com.bpt.kori.domain.auth.dto.EmailVerificationRequest.builder()
                .email("jihoon@bpt.app")
                .purpose("RESET_PASSWORD")
                .username("unknown_user")
                .build();

        assertThatThrownBy(() -> authService.requestEmailVerification(req))
                .isInstanceOf(CustomException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.USER_NOT_FOUND);
    }

    @Test
    @DisplayName("비밀번호 재설정 인증번호 발송 요청 시 아이디와 이메일 불일치하면 USER_NOT_FOUND 예외 발생")
    void requestEmailVerification_resetPassword_emailMismatch() {
        User user = User.builder()
                .id(1L)
                .username("jihoon_kim")
                .email("jihoon@bpt.app")
                .build();

        given(userRepository.findByUsername("jihoon_kim")).willReturn(java.util.Optional.of(user));

        var req = com.bpt.kori.domain.auth.dto.EmailVerificationRequest.builder()
                .email("other@bpt.app")
                .purpose("RESET_PASSWORD")
                .username("jihoon_kim")
                .build();

        assertThatThrownBy(() -> authService.requestEmailVerification(req))
                .isInstanceOf(CustomException.class)
                .hasFieldOrPropertyWithValue("errorCode", ErrorCode.USER_NOT_FOUND);
    }
}
