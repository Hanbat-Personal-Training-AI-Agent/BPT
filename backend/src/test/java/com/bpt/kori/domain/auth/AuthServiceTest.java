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
        validSignUpRequest.setTermsAgreed(true);
        validSignUpRequest.setPrivacyAgreed(true);
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
                    .privacyAgreed(user.getPrivacyAgreed())
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
}
