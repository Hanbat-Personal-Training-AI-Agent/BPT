package com.bpt.kori.security;

import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.io.Decoders;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.Date;

import static org.assertj.core.api.Assertions.assertThat;

class JwtTokenProviderTest {

    // 테스트 전용 키 (운영 키 아님)
    private static final String TEST_SECRET =
            "dGVzdF9vbmx5X2p3dF9zZWNyZXRfZm9yX3VuaXRfdGVzdHNfMDEyMzQ1Njc4OWFiY2RlZg==";

    private final JwtTokenProvider provider = new JwtTokenProvider(TEST_SECRET, 3_600_000L, 1_209_600_000L);

    @Test
    @DisplayName("액세스 토큰은 API 인증에만, 리프레시 토큰은 갱신에만 쓸 수 있다")
    void tokenTypesAreNotInterchangeable() {
        String access = provider.generateAccessToken(1L, "tester", "tester@bpt.app");
        String refresh = provider.generateRefreshToken(1L);

        assertThat(provider.validateAccessToken(access)).isTrue();
        assertThat(provider.validateRefreshToken(access)).isFalse();

        assertThat(provider.validateRefreshToken(refresh)).isTrue();
        assertThat(provider.validateAccessToken(refresh)).isFalse();
    }

    @Test
    @DisplayName("token_type 클레임 이전에 발급된 토큰도 원래 용도로만 통과한다")
    void legacyTokensKeepTheirOriginalRole() {
        var key = Keys.hmacShaKeyFor(Decoders.BASE64.decode(TEST_SECRET));
        Date exp = new Date(System.currentTimeMillis() + 60_000);
        String legacyAccess = Jwts.builder().subject("1").claim("username", "tester").expiration(exp).signWith(key).compact();
        String legacyRefresh = Jwts.builder().subject("1").expiration(exp).signWith(key).compact();

        assertThat(provider.validateAccessToken(legacyAccess)).isTrue();
        assertThat(provider.validateRefreshToken(legacyAccess)).isFalse();
        assertThat(provider.validateRefreshToken(legacyRefresh)).isTrue();
        assertThat(provider.validateAccessToken(legacyRefresh)).isFalse();
    }

    @Test
    @DisplayName("다른 키로 서명한 토큰은 거부한다")
    void rejectsForeignSignature() {
        JwtTokenProvider other = new JwtTokenProvider(
                "b3RoZXJfdGVzdF9vbmx5X2tleV9mb3JfdW5pdF90ZXN0c18wMTIzNDU2Nzg5YWJjZGVm", 3_600_000L, 1_209_600_000L);
        String forged = other.generateAccessToken(1L, "tester", "tester@bpt.app");

        assertThat(provider.validateAccessToken(forged)).isFalse();
    }
}
