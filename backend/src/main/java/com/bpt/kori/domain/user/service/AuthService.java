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

import java.security.SecureRandom;
import java.time.Duration;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

@Slf4j
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class AuthService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtTokenProvider tokenProvider;
    private final EmailService emailService;

    // 이메일 인증번호 저장소: email -> VerificationEntry
    private final Map<String, VerificationEntry> verificationStore = new ConcurrentHashMap<>();
    // 비동기 메일 발송 실패 기록소: email -> 실패 시각
    private final Map<String, LocalDateTime> failedEmailStore = new ConcurrentHashMap<>();
    // 계정 찾기 및 비밀번호 재설정용 1회용 인증 토큰 저장소: verificationToken -> VerificationTokenEntry
    private final Map<String, VerificationTokenEntry> verificationTokenStore = new ConcurrentHashMap<>();
    // 인증 완료 이메일 저장소 (하위 호환용)
    private final Map<String, LocalDateTime> verifiedEmailStore = new ConcurrentHashMap<>();

    public record VerificationEntry(
            String code,
            LocalDateTime expiresAt,
            LocalDateTime requestedAt,
            AtomicInteger attemptCount
    ) {}

    public record VerificationTokenEntry(
            String email,
            LocalDateTime expiresAt
    ) {}

    @Transactional
    public TokenResponse login(LoginRequest request) {
        String username = request.getUsername().trim();
        User user = userRepository.findByUsername(username)
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

        if (Boolean.FALSE.equals(request.getTermsAgreed()) || request.getTermsAgreed() == null) {
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
                .marketingConsent(false)
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

    @Transactional
    public TokenResponse refresh(RefreshTokenRequest request) {
        String refreshToken = request.getRefreshToken();
        if (refreshToken == null || refreshToken.isBlank() || !tokenProvider.validateToken(refreshToken.trim())) {
            throw new CustomException(ErrorCode.TOKEN_EXPIRED);
        }

        Long userId;
        try {
            userId = tokenProvider.getUserIdFromToken(refreshToken.trim());
        } catch (Exception e) {
            throw new CustomException(ErrorCode.TOKEN_EXPIRED);
        }

        User user = userRepository.findById(userId)
                .orElseThrow(() -> new CustomException(ErrorCode.USER_NOT_FOUND));

        String newAccessToken = tokenProvider.generateAccessToken(user.getId(), user.getUsername(), user.getEmail());
        String newRefreshToken = tokenProvider.generateRefreshToken(user.getId());

        return TokenResponse.builder()
                .token(newAccessToken)
                .accessToken(newAccessToken)
                .refreshToken(newRefreshToken)
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
        String email = request.getEmail().trim().toLowerCase();
        String purpose = request.getPurpose() != null ? request.getPurpose().trim() : null;
        String username = request.getUsername() != null ? request.getUsername().trim() : null;

        // 비밀번호 재설정 시 아이디 확인:
        // purpose가 RESET_PASSWORD이고 username이 오면, 같은 계정일 때만 발송하고 아니면 404 USER_NOT_FOUND
        if ("RESET_PASSWORD".equalsIgnoreCase(purpose)) {
            if (username != null && !username.isBlank()) {
                User user = userRepository.findByUsername(username)
                        .orElseThrow(() -> new CustomException(ErrorCode.USER_NOT_FOUND));
                if (!user.getEmail().trim().equalsIgnoreCase(email)) {
                    log.warn("[VERIFY EMAIL RESET_PASSWORD MISMATCH] username {} has email {}, but request email is {}",
                            username, user.getEmail(), email);
                    throw new CustomException(ErrorCode.USER_NOT_FOUND);
                }
            } else {
                if (!userRepository.existsByEmail(email)) {
                    log.warn("[VERIFY EMAIL RESET_PASSWORD NOT FOUND] email {} not found", email);
                    throw new CustomException(ErrorCode.USER_NOT_FOUND);
                }
            }
        }

        // 4번: 재발송은 1분 간격 제한
        VerificationEntry existing = verificationStore.get(email);
        if (existing != null) {
            long secondsSinceLastRequest = Duration.between(existing.requestedAt(), LocalDateTime.now()).getSeconds();
            if (secondsSinceLastRequest < 60) {
                log.warn("[EMAIL RESEND RATE LIMIT] Email {} attempted resend after {} seconds", email, secondsSinceLastRequest);
                throw new CustomException(ErrorCode.RESEND_COOLDOWN_ACTIVE);
            }
        }

        int randomCode = 100000 + new SecureRandom().nextInt(900000);
        String code = String.valueOf(randomCode);
        LocalDateTime expiresAt = LocalDateTime.now().plusMinutes(5);

        // 10번: 인증번호 저장 후 바로 응답하고 메일은 비동기로 발송
        verificationStore.put(email, new VerificationEntry(code, expiresAt, LocalDateTime.now(), new AtomicInteger(0)));
        failedEmailStore.remove(email);

        // 3번, 5번, 10번: 비동기 발송, 목적별 문구 분기, 인증번호 로그 미노출, 발송 실패 시 폐기
        emailService.sendVerificationEmailAsync(
                email,
                code,
                request.getPurpose(),
                (error) -> {
                    log.error("[EMAIL ASYNC FAILURE] Invalidation triggered for {}", email);
                    verificationStore.remove(email);
                    failedEmailStore.put(email, LocalDateTime.now().plusMinutes(5));
                }
        );

        return EmailVerificationResponse.builder()
                .success(true)
                .message("인증번호가 이메일로 발송되었습니다. (5분 내 입력)")
                .build();
    }

    public EmailVerificationConfirmResponse confirmEmailVerification(EmailVerificationConfirmRequest request) {
        String email = request.getEmail().trim().toLowerCase();
        String inputCode = request.getCode() != null ? request.getCode().trim() : "";

        // 메일 비동기 발송이 실패했을 경우 (3번)
        if (failedEmailStore.containsKey(email)) {
            failedEmailStore.remove(email);
            throw new CustomException(ErrorCode.EMAIL_SEND_FAILED);
        }

        VerificationEntry entry = verificationStore.get(email);
        if (entry == null) {
            return EmailVerificationConfirmResponse.builder()
                    .verified(false)
                    .success(false)
                    .message("인증번호 요청 내역이 없거나 만료되었습니다.")
                    .build();
        }

        if (LocalDateTime.now().isAfter(entry.expiresAt())) {
            verificationStore.remove(email);
            return EmailVerificationConfirmResponse.builder()
                    .verified(false)
                    .success(false)
                    .message("인증번호 유효시간(5분)이 만료되었습니다. 다시 요청해 주세요.")
                    .build();
        }

        // 4번: 틀린 횟수 확인 (5회 틀리면 번호 폐기)
        if (!entry.code().equals(inputCode)) {
            int attempts = entry.attemptCount().incrementAndGet();
            if (attempts >= 5) {
                verificationStore.remove(email);
                log.warn("[EMAIL VERIFICATION BRUTE FORCE BLOCKED] Email {} reached 5 attempts. Verification entry removed.", email);
                throw new CustomException(ErrorCode.TOO_MANY_VERIFICATION_ATTEMPTS);
            }
            return EmailVerificationConfirmResponse.builder()
                    .verified(false)
                    .success(false)
                    .message(String.format("인증번호가 일치하지 않습니다. (5회 중 %d회 실패)", attempts))
                    .build();
        }

        // 인증 성공 시 인증번호 폐기 및 1회용 verificationToken 발급 (10분 유효) (1번)
        verificationStore.remove(email);
        String verificationToken = "vt_" + UUID.randomUUID().toString().replace("-", "").substring(0, 16);
        verificationTokenStore.put(verificationToken, new VerificationTokenEntry(email, LocalDateTime.now().plusMinutes(10)));
        verifiedEmailStore.put(email, LocalDateTime.now().plusMinutes(15)); // 호환용

        log.info("[EMAIL VERIFIED] Email {} verified successfully. verificationToken generated.", email);
        return EmailVerificationConfirmResponse.builder()
                .verified(true)
                .success(true)
                .verificationToken(verificationToken)
                .message("이메일 인증이 완료되었습니다.")
                .build();
    }

    public FindUsernameResponse findUsername(FindUsernameRequest request) {
        String email = null;

        // 1. verificationToken 기반 인증 (권장)
        if (request.getVerificationToken() != null && !request.getVerificationToken().isBlank()) {
            String token = request.getVerificationToken().trim();
            VerificationTokenEntry tokenEntry = verificationTokenStore.get(token);
            if (tokenEntry == null || LocalDateTime.now().isAfter(tokenEntry.expiresAt())) {
                verificationTokenStore.remove(token);
                throw new CustomException(ErrorCode.INVALID_VERIFICATION_TOKEN);
            }
            email = tokenEntry.email();
            // 1회용 토큰 즉시 파기
            verificationTokenStore.remove(token);
        } else if (request.getEmail() != null && !request.getEmail().isBlank()) {
            // 하위 호환: email + code 직접 전달 또는 이전 인증 기록 확인
            String reqEmail = request.getEmail().trim().toLowerCase();
            if (!isEmailVerified(reqEmail, request.getCode())) {
                throw new CustomException(ErrorCode.EMAIL_NOT_VERIFIED);
            }
            email = reqEmail;
        } else {
            throw new CustomException(ErrorCode.INVALID_VERIFICATION_TOKEN);
        }

        User user = userRepository.findByEmail(email)
                .orElseThrow(() -> new CustomException(ErrorCode.USER_NOT_FOUND));

        String username = user.getUsername();
        String masked = maskUsername(username);

        return FindUsernameResponse.builder()
                .success(true)
                .username(username)
                .maskedUsername(masked)
                .message("아이디 조회가 완료되었습니다.")
                .build();
    }

    @Transactional
    public ResetPasswordResponse resetPassword(ResetPasswordRequest request) {
        String email = request.getEmail() != null ? request.getEmail().trim().toLowerCase() : "";
        String username = request.getUsername() != null ? request.getUsername().trim() : "";
        String newPassword = request.getNewPassword() != null ? request.getNewPassword().trim() : "";

        if (newPassword.length() < 6) {
            throw new CustomException(ErrorCode.INVALID_INPUT_VALUE);
        }

        // 1. verificationToken 기반 검증
        if (request.getVerificationToken() != null && !request.getVerificationToken().isBlank()) {
            String token = request.getVerificationToken().trim();
            VerificationTokenEntry tokenEntry = verificationTokenStore.get(token);
            if (tokenEntry == null || LocalDateTime.now().isAfter(tokenEntry.expiresAt())) {
                verificationTokenStore.remove(token);
                throw new CustomException(ErrorCode.INVALID_VERIFICATION_TOKEN);
            }
            // 토큰에 바인딩된 이메일과 요청의 이메일 일치 확인
            if (!tokenEntry.email().equalsIgnoreCase(email)) {
                throw new CustomException(ErrorCode.INVALID_VERIFICATION_TOKEN);
            }
            // 1회용 토큰 즉시 파기
            verificationTokenStore.remove(token);
        } else {
            // 하위 호환
            if (!isEmailVerified(email, request.getCode())) {
                throw new CustomException(ErrorCode.EMAIL_NOT_VERIFIED);
            }
        }

        // 아이디와 이메일이 같은 계정인지 검증
        User user;
        if (!username.isBlank()) {
            user = userRepository.findByUsername(username)
                    .orElseThrow(() -> new CustomException(ErrorCode.USER_NOT_FOUND));
            if (!user.getEmail().equalsIgnoreCase(email)) {
                log.warn("[PASSWORD RESET MISMATCH] username {} has email {}, but request email is {}",
                        username, user.getEmail(), email);
                throw new CustomException(ErrorCode.USER_NOT_FOUND);
            }
        } else {
            user = userRepository.findByEmail(email)
                    .orElseThrow(() -> new CustomException(ErrorCode.USER_NOT_FOUND));
        }

        user.setPassword(passwordEncoder.encode(newPassword));
        userRepository.save(user);

        verifiedEmailStore.remove(email);
        log.info("[PASSWORD RESET] Successfully reset password for email: {}, username: {}", email, user.getUsername());

        return ResetPasswordResponse.builder()
                .success(true)
                .message("비밀번호가 변경되었습니다.")
                .build();
    }

    private boolean isEmailVerified(String email, String code) {
        if (code != null && !code.isBlank()) {
            VerificationEntry entry = verificationStore.get(email);
            if (entry != null && !LocalDateTime.now().isAfter(entry.expiresAt()) && entry.code().equals(code.trim())) {
                verificationStore.remove(email);
                return true;
            }
        }
        LocalDateTime verifiedUntil = verifiedEmailStore.get(email);
        return verifiedUntil != null && LocalDateTime.now().isBefore(verifiedUntil);
    }

    private String maskUsername(String username) {
        if (username == null || username.isEmpty()) {
            return "";
        }
        if (username.length() <= 3) {
            return username.charAt(0) + "*".repeat(username.length() - 1);
        }
        return username.substring(0, 3) + "*".repeat(username.length() - 3);
    }
}
