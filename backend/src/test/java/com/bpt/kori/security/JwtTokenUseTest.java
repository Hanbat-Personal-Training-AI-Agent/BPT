package com.bpt.kori.security;

import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.AfterEach;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.security.core.context.SecurityContextHolder;
import java.util.Base64;
import java.util.Date;
import java.util.Map;
import static org.assertj.core.api.Assertions.assertThat;

class JwtTokenUseTest {
    private static final byte[] KEY = "test-only-token-use-key-000000000000000000000000000000000000000000".getBytes();
    private final JwtTokenProvider provider = new JwtTokenProvider(Base64.getEncoder().encodeToString(KEY), 3600000, 1209600000);

    private String signed(Map<String,Object> claims) {
        return Jwts.builder().claims(claims).subject("42")
                .expiration(new Date(System.currentTimeMillis()+60000))
                .signWith(Keys.hmacShaKeyFor(KEY)).compact();
    }
    private String rawSigned(String payload) throws Exception {
        var encoder = Base64.getUrlEncoder().withoutPadding();
        String input = encoder.encodeToString("{\"alg\":\"HS512\"}".getBytes()) + "."
                + encoder.encodeToString(payload.getBytes());
        var mac = javax.crypto.Mac.getInstance("HmacSHA512");
        mac.init(new javax.crypto.spec.SecretKeySpec(KEY, "HmacSHA512"));
        return input + "." + encoder.encodeToString(mac.doFinal(input.getBytes()));
    }
    @AfterEach void clearContext() { SecurityContextHolder.clearContext(); }

    @Test void newTokensAreClassSeparated() {
        String access = provider.generateAccessToken(42L,"owner","owner@example.invalid");
        String refresh = provider.generateRefreshToken(42L);
        assertThat(provider.validateAccessToken(access)).isTrue();
        assertThat(provider.validateRefreshToken(refresh)).isTrue();
        assertThat(provider.validateAccessToken(refresh)).isFalse();
        assertThat(provider.validateToken(refresh)).isFalse();
        assertThat(provider.validateRefreshToken(access)).isFalse();
    }
    @Test void legacySignedTokensMigrateWithoutCrossUse() {
        String access = signed(Map.of("username","owner","email","owner@example.invalid"));
        String refresh = signed(Map.of());
        assertThat(provider.validateAccessToken(access)).isTrue();
        assertThat(provider.validateRefreshToken(refresh)).isTrue();
        assertThat(provider.validateAccessToken(refresh)).isFalse();
        assertThat(provider.validateRefreshToken(access)).isFalse();
    }
    @Test void unknownExplicitTypesAndAmbiguousIdentityNeverFallback() {
        for (String type : new String[]{"refresh","future","ACCESS",""}) {
            assertThat(provider.validateAccessToken(signed(Map.of("token_use",type,"username","owner","email","owner@example.invalid")))).isFalse();
        }
        assertThat(provider.validateAccessToken(signed(Map.of("username","owner")))).isFalse();
        assertThat(provider.validateRefreshToken(signed(Map.of("username","owner")))).isFalse();
        assertThat(provider.validateRefreshToken(signed(Map.of("token_use","access")))).isFalse();
        assertThat(provider.validateAccessToken("malformed")).isFalse();
    }
    @Test void refreshBearerCannotAuthenticateFilter() throws Exception {
        var filter = new JwtAuthenticationFilter(provider);
        var request = new MockHttpServletRequest();
        request.addHeader("Authorization","Bearer "+provider.generateRefreshToken(42L));
        filter.doFilter(request,new MockHttpServletResponse(),new MockFilterChain());
        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
        request = new MockHttpServletRequest();
        request.addHeader("Authorization","Bearer "+provider.generateAccessToken(42L,"owner","owner@example.invalid"));
        filter.doFilter(request,new MockHttpServletResponse(),new MockFilterChain());
        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNotNull();
    }
    @Test void malformedSignedTypesAndExpiredTokensNeverAuthenticate() throws Exception {
        long future = System.currentTimeMillis()/1000 + 600;
        String[] payloads = {
            "{\"sub\":\"42\",\"exp\":"+future+",\"token_use\":null,\"username\":\"u\",\"email\":\"e\"}",
            "{\"sub\":\"42\",\"exp\":"+future+",\"token_use\":3,\"username\":\"u\",\"email\":\"e\"}",
            "{\"sub\":\"42\",\"exp\":"+future+",\"token_use\":\"access\",\"username\":[],\"email\":\"e\"}",
            "{\"sub\":\"42\",\"username\":\"u\",\"email\":\"e\"}",
            "{\"sub\":\"42\",\"exp\":1,\"username\":\"u\",\"email\":\"e\"}",
            "{\"sub\":{},\"exp\":"+future+",\"username\":\"u\",\"email\":\"e\"}",
            "{\"sub\":\"42\",\"exp\":"+future+",\"token_use\":\"refresh\",\"token_use\":\"access\",\"username\":\"u\",\"email\":\"e\"}",
            "{\"sub\":\"9999999999999999999\",\"exp\":"+future+",\"username\":\"u\",\"email\":\"e\"}"
        };
        var filter = new JwtAuthenticationFilter(provider);
        for (String payload : payloads) {
            String token = rawSigned(payload);
            assertThat(provider.validateAccessToken(token)).isFalse();
            assertThat(provider.validateRefreshToken(token)).isFalse();
            var request = new MockHttpServletRequest();
            request.addHeader("Authorization", "Bearer " + token);
            filter.doFilter(request, new MockHttpServletResponse(), new MockFilterChain());
            assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
        }
    }
}
