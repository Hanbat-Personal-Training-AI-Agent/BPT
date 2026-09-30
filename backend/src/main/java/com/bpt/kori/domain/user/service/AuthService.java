package com.bpt.kori.domain.user.service;

import com.bpt.kori.common.exception.CustomException;
import com.bpt.kori.common.exception.ErrorCode;
import com.bpt.kori.domain.auth.dto.*;
import com.bpt.kori.domain.user.dto.UserDto;
import com.bpt.kori.domain.user.entity.User;
import com.bpt.kori.domain.user.repository.UserRepository;
import com.bpt.kori.security.JwtTokenProvider;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;

@Slf4j
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class AuthService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtTokenProvider tokenProvider;

    @Transactional
    public TokenResponse login(LoginRequest request) {
        String identifier = request.getEmail().trim();
        User user = userRepository.findByEmail(identifier)
                .or(() -> userRepository.findByUsername(identifier))
                .orElseThrow(() -> new CustomException(ErrorCode.INVALID_CREDENTIALS));

        if (!passwordEncoder.matches(request.getPassword(), user.getPassword())) {
            throw new CustomException(ErrorCode.INVALID_CREDENTIALS);
        }

        String accessToken = tokenProvider.generateAccessToken(user.getId(), user.getUsername(), user.getEmail());
        String refreshToken = tokenProvider.generateRefreshToken(user.getId());

        return TokenResponse.builder()
                .token(accessToken)
                .accessToken(accessToken)
                .refreshToken(refreshToken)
                .tokenType("Bearer")
                .expiresIn(tokenProvider.getAccessTokenExpirationSeconds())
                .user(UserDto.fromEntity(user))
                .build();
    }

    @Transactional
    public TokenResponse signUp(SignUpRequest request) {
        String email = request.getEmail().trim();
        String username = request.getUsername().trim();

        if (userRepository.existsByEmail(email)) {
            throw new CustomException(ErrorCode.EMAIL_ALREADY_EXISTS);
        }
        if (userRepository.existsByUsername(username)) {
            throw new CustomException(ErrorCode.USERNAME_ALREADY_EXISTS);
        }

        if (Boolean.FALSE.equals(request.getTermsAgreed()) || Boolean.FALSE.equals(request.getPrivacyAgreed())
                || request.getTermsAgreed() == null || request.getPrivacyAgreed() == null) {
            throw new CustomException(ErrorCode.TERMS_NOT_AGREED);
        }

        LocalDate parsedBirthDate = null;
        if (request.getBirthDate() != null && !request.getBirthDate().isBlank()) {
            try {
                parsedBirthDate = LocalDate.parse(request.getBirthDate().trim());
            } catch (Exception e) {
                log.warn("Invalid birthDate format: {}", request.getBirthDate());
            }
        }

        User user = User.builder()
                .email(email)
                .username(username)
                .password(passwordEncoder.encode(request.getPassword()))
                .name(request.getName() != null && !request.getName().isBlank() ? request.getName() : username)
                .phoneNumber(request.getPhoneNumber() != null ? request.getPhoneNumber().trim() : null)
                .birthDate(parsedBirthDate)
                .termsAgreed(Boolean.TRUE.equals(request.getTermsAgreed()))
                .privacyAgreed(Boolean.TRUE.equals(request.getPrivacyAgreed()))
                .build();

        userRepository.save(user);

        String accessToken = tokenProvider.generateAccessToken(user.getId(), user.getUsername(), user.getEmail());
        String refreshToken = tokenProvider.generateRefreshToken(user.getId());

        return TokenResponse.builder()
                .token(accessToken)
                .accessToken(accessToken)
                .refreshToken(refreshToken)
                .tokenType("Bearer")
                .expiresIn(tokenProvider.getAccessTokenExpirationSeconds())
                .user(UserDto.fromEntity(user))
                .build();
    }

    public CheckUsernameResponse checkUsername(String username) {
        if (username == null || username.trim().isEmpty()) {
            throw new CustomException(ErrorCode.INVALID_USERNAME_FORMAT);
        }
        boolean exists = userRepository.existsByUsername(username.trim());
        if (exists) {
            return new CheckUsernameResponse(false, "이미 사용 중인 아이디입니다.");
        }
        return new CheckUsernameResponse(true, "사용 가능한 아이디입니다.");
    }

    public EmailVerificationResponse requestEmailVerification(EmailVerificationRequest request) {
        int randomCode = 100000 + (int) (Math.random() * 900000);
        String code = String.valueOf(randomCode);
        log.info("==================================================");
        log.info("[MOCK EMAIL VERIFICATION] Target Email: {}, 6-digit Code: {}", request.getEmail().trim(), code);
        log.info("==================================================");
        return EmailVerificationResponse.builder()
                .success(true)
                .message("인증번호가 발송되었습니다. (테스트 환경: 서버 로그 확인)")
                .build();
    }

    public EmailVerificationConfirmResponse confirmEmailVerification(EmailVerificationConfirmRequest request) {
        log.info("[MOCK EMAIL CONFIRM] Email: {}, Input Code: {} -> Result: Verified(true)",
                request.getEmail().trim(), request.getCode().trim());
        return EmailVerificationConfirmResponse.builder()
                .verified(true)
                .message("이메일 인증이 완료되었습니다.")
                .build();
    }
}
