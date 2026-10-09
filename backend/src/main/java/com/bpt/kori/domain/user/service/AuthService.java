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
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.SecureRandom;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@Slf4j
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class AuthService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtTokenProvider tokenProvider;
    private final JavaMailSender mailSender;

    private final Map<String, VerificationEntry> verificationStore = new ConcurrentHashMap<>();

    public record VerificationEntry(String code, LocalDateTime expiresAt) {}

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
        String email = request.getEmail().trim().toLowerCase();
        int randomCode = 100000 + new SecureRandom().nextInt(900000);
        String code = String.valueOf(randomCode);
        LocalDateTime expiresAt = LocalDateTime.now().plusMinutes(5);

        verificationStore.put(email, new VerificationEntry(code, expiresAt));

        try {
            SimpleMailMessage mailMessage = new SimpleMailMessage();
            mailMessage.setTo(email);
            mailMessage.setSubject("[BPT] 이메일 인증번호 안내");
            mailMessage.setText("안녕하세요, BPT(Body Posture Training) 서비스입니다.\n\n"
                    + "회원가입 본인 인증을 위한 6자리 인증번호는 다음과 같습니다.\n\n"
                    + "인증번호: [" + code + "]\n\n"
                    + "인증번호는 발송 시점으로부터 5분간 유효합니다.\n\n"
                    + "감사합니다.");
            mailSender.send(mailMessage);
            log.info("[EMAIL SENT] Successfully sent verification code to {}", email);
        } catch (Exception e) {
            log.warn("[EMAIL SEND WARNING] Could not send email via SMTP to {}: {}. Verification code is preserved in memory: {}",
                    email, e.getMessage(), code);
        }

        return EmailVerificationResponse.builder()
                .success(true)
                .message("인증번호가 이메일로 발송되었습니다. (5분 내 입력)")
                .build();
    }

    public EmailVerificationConfirmResponse confirmEmailVerification(EmailVerificationConfirmRequest request) {
        String email = request.getEmail().trim().toLowerCase();
        String inputCode = request.getCode() != null ? request.getCode().trim() : "";

        VerificationEntry entry = verificationStore.get(email);
        if (entry == null) {
            return EmailVerificationConfirmResponse.builder()
                    .verified(false)
                    .message("인증번호 요청 내역이 없거나 만료되었습니다.")
                    .build();
        }

        if (LocalDateTime.now().isAfter(entry.expiresAt())) {
            verificationStore.remove(email);
            return EmailVerificationConfirmResponse.builder()
                    .verified(false)
                    .message("인증번호 유효시간(5분)이 만료되었습니다. 다시 요청해 주세요.")
                    .build();
        }

        if (!entry.code().equals(inputCode)) {
            return EmailVerificationConfirmResponse.builder()
                    .verified(false)
                    .message("인증번호가 일치하지 않습니다.")
                    .build();
        }

        verificationStore.remove(email);
        log.info("[EMAIL VERIFIED] Email {} verified successfully", email);
        return EmailVerificationConfirmResponse.builder()
                .verified(true)
                .message("이메일 인증이 완료되었습니다.")
                .build();
    }
}
