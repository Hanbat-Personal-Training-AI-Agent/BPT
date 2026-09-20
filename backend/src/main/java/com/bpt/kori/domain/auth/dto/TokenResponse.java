package com.bpt.kori.domain.auth.dto;

import com.bpt.kori.domain.user.dto.UserDto;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;

@Getter
@AllArgsConstructor
@Builder
public class TokenResponse {

    private final String token; // Flutter AuthService expects 'token'
    private final String accessToken;
    private final String refreshToken;
    private final String tokenType;
    private final Long expiresIn;
    private final UserDto user; // Flutter AuthService expects 'user'
}
