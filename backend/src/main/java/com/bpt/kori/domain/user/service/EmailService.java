package com.bpt.kori.domain.user.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

import java.util.concurrent.CompletableFuture;
import java.util.function.Consumer;

@Slf4j
@Service
@RequiredArgsConstructor
public class EmailService {

    private final JavaMailSender mailSender;

    @Async
    public CompletableFuture<Void> sendVerificationEmailAsync(
            String email,
            String code,
            String purpose,
            Consumer<Throwable> onFailure
    ) {
        try {
            String purposeUpper = purpose != null ? purpose.trim().toUpperCase() : "SIGN_UP";
            String purposeText;
            String subjectText;

            switch (purposeUpper) {
                case "FIND_ACCOUNT":
                case "FIND_USERNAME":
                case "RESET_PASSWORD":
                case "ACCOUNT_RECOVERY":
                    purposeText = "계정 찾기 본인 인증을 위한";
                    subjectText = "[BPT] 계정 찾기 이메일 인증번호 안내";
                    break;
                case "SIGN_UP":
                default:
                    purposeText = "회원가입 본인 인증을 위한";
                    subjectText = "[BPT] 회원가입 이메일 인증번호 안내";
                    break;
            }

            SimpleMailMessage mailMessage = new SimpleMailMessage();
            mailMessage.setTo(email);
            mailMessage.setSubject(subjectText);
            mailMessage.setText("안녕하세요, BPT(Body Posture Training) 서비스입니다.\n\n"
                    + purposeText + " 6자리 인증번호는 다음과 같습니다.\n\n"
                    + "인증번호: [" + code + "]\n\n"
                    + "인증번호는 발송 시점으로부터 5분간 유효합니다.\n\n"
                    + "감사합니다.");

            mailSender.send(mailMessage);
            // 인증코드는 보안상 로그에 절대 남기지 않고 성공 여부 및 이메일 주소만 기록
            log.info("[EMAIL SENT] Successfully sent verification email to {}", email);
            return CompletableFuture.completedFuture(null);
        } catch (Exception e) {
            // 인증코드는 보안상 에러 로그에도 남기지 않음
            log.error("[EMAIL SEND FAILED] Failed to send verification email to {}: {}", email, e.getMessage());
            if (onFailure != null) {
                try {
                    onFailure.accept(e);
                } catch (Exception callbackEx) {
                    log.error("[EMAIL FAILURE CALLBACK ERROR] Error executing failure callback: {}", callbackEx.getMessage());
                }
            }
            return CompletableFuture.failedFuture(e);
        }
    }
}
