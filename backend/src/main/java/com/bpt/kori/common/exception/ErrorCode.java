package com.bpt.kori.common.exception;

import lombok.Getter;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;

@Getter
@RequiredArgsConstructor
public enum ErrorCode {

    // 400 Bad Request
    INVALID_INPUT_VALUE(HttpStatus.BAD_REQUEST, "INVALID_INPUT_VALUE", "입력값을 다시 확인해 주세요."),
    INVALID_USERNAME_FORMAT(HttpStatus.BAD_REQUEST, "INVALID_USERNAME_FORMAT", "아이디는 영문 소문자, 숫자, 언더바(_)만 사용하여 4~20자 이내로 입력해 주세요."),
    PASSWORD_CONFIRM_MISMATCH(HttpStatus.BAD_REQUEST, "PASSWORD_CONFIRM_MISMATCH", "비밀번호가 일치하지 않습니다. 다시 확인해 주세요."),
    TERMS_NOT_AGREED(HttpStatus.BAD_REQUEST, "TERMS_NOT_AGREED", "이용약관 및 개인정보 처리방침에 동의해 주세요."),

    // 401 Unauthorized
    INVALID_CREDENTIALS(HttpStatus.UNAUTHORIZED, "INVALID_CREDENTIALS", "이메일 또는 비밀번호를 다시 확인해 주세요."),
    TOKEN_EXPIRED(HttpStatus.UNAUTHORIZED, "TOKEN_EXPIRED", "인증 토큰이 만료되었습니다. 다시 로그인해 주세요."),
    UNAUTHORIZED(HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "로그인이 필요한 요청입니다."),

    // 403 Forbidden
    FORBIDDEN(HttpStatus.FORBIDDEN, "FORBIDDEN", "접근 권한이 없습니다."),
    SESSION_ACCESS_DENIED(HttpStatus.FORBIDDEN, "SESSION_ACCESS_DENIED", "본인의 운동 데이터만 접근할 수 있습니다."),

    // 404 Not Found
    USER_NOT_FOUND(HttpStatus.NOT_FOUND, "USER_NOT_FOUND", "사용자를 찾을 수 없습니다."),
    EXERCISE_NOT_FOUND(HttpStatus.NOT_FOUND, "EXERCISE_NOT_FOUND", "해당 운동 종목을 찾을 수 없습니다."),
    RECORD_NOT_FOUND(HttpStatus.NOT_FOUND, "RECORD_NOT_FOUND", "해당 운동 기록을 찾을 수 없습니다."),
    ANALYSIS_NOT_FOUND(HttpStatus.NOT_FOUND, "ANALYSIS_NOT_FOUND", "체형 측정 결과 데이터를 찾을 수 없습니다."),

    // 409 Conflict
    EMAIL_ALREADY_EXISTS(HttpStatus.CONFLICT, "EMAIL_ALREADY_EXISTS", "이미 가입된 이메일 주소입니다."),
    USERNAME_ALREADY_EXISTS(HttpStatus.CONFLICT, "USERNAME_ALREADY_EXISTS", "이미 사용 중인 아이디입니다."),

    // 500 Internal Server Error
    INTERNAL_SERVER_ERROR(HttpStatus.INTERNAL_SERVER_ERROR, "INTERNAL_SERVER_ERROR", "서버 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.");

    private final HttpStatus status;
    private final String code;
    private final String message;
}
