package com.bpt.kori.domain.user.service;

import com.bpt.kori.common.exception.CustomException;
import com.bpt.kori.common.exception.ErrorCode;
import com.bpt.kori.domain.auth.dto.*;
import com.bpt.kori.domain.user.dto.UserDto;
import com.bpt.kori.domain.user.entity.User;
import com.bpt.kori.domain.user.repository.UserRepository;
import com.bpt.kori.security.JwtTokenProvider;
import lombok.RequiredArgsConstructor;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class AuthService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtTokenProvider tokenProvider;

    @Transactional
    public TokenResponse login(LoginRequest request) {
        User user = userRepository.findByEmail(request.getEmail().trim())
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

        User user = User.builder()
                .email(email)
                .username(username)
                .password(passwordEncoder.encode(request.getPassword()))
                .name(request.getName() != null && !request.getName().isBlank() ? request.getName() : username)
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
}
