package com.bpt.kori.security;

import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.io.Decoders;
import io.jsonwebtoken.security.Keys;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import java.util.Date;

@Slf4j
@Component
public class JwtTokenProvider {

    private static final ObjectMapper CLAIMS_JSON = new ObjectMapper()
            .enable(JsonParser.Feature.STRICT_DUPLICATE_DETECTION);
    private final SecretKey secretKey;
    private final long accessTokenExpirationMs;
    private final long refreshTokenExpirationMs;

    public JwtTokenProvider(
            @Value("${jwt.secret}") String secret,
            @Value("${jwt.access-token-expiration-ms}") long accessTokenExpirationMs,
            @Value("${jwt.refresh-token-expiration-ms}") long refreshTokenExpirationMs
    ) {
        byte[] keyBytes = Decoders.BASE64.decode(secret);
        this.secretKey = Keys.hmacShaKeyFor(keyBytes);
        this.accessTokenExpirationMs = accessTokenExpirationMs;
        this.refreshTokenExpirationMs = refreshTokenExpirationMs;
    }

    public String generateAccessToken(Long userId, String username, String email) {
        Date now = new Date();
        Date expiryDate = new Date(now.getTime() + accessTokenExpirationMs);

        return Jwts.builder()
                .subject(String.valueOf(userId))
                .claim("token_use", "access")
                .claim("username", username)
                .claim("email", email)
                .issuedAt(now)
                .expiration(expiryDate)
                .signWith(secretKey)
                .compact();
    }

    public String generateRefreshToken(Long userId) {
        Date now = new Date();
        Date expiryDate = new Date(now.getTime() + refreshTokenExpirationMs);

        return Jwts.builder()
                .subject(String.valueOf(userId))
                .claim("token_use", "refresh")
                .issuedAt(now)
                .expiration(expiryDate)
                .signWith(secretKey)
                .compact();
    }

    public Long getUserIdFromToken(String token) {
        Claims claims = Jwts.parser()
                .verifyWith(secretKey)
                .build()
                .parseSignedClaims(token)
                .getPayload();

        return Long.parseLong(claims.getSubject());
    }

    public String getUsernameFromToken(String token) {
        Claims claims = Jwts.parser()
                .verifyWith(secretKey)
                .build()
                .parseSignedClaims(token)
                .getPayload();

        return claims.get("username", String.class);
    }

    public String getEmailFromToken(String token) {
        Claims claims = Jwts.parser()
                .verifyWith(secretKey)
                .build()
                .parseSignedClaims(token)
                .getPayload();

        return claims.get("email", String.class);
    }

    /** Kept for callers migrating from generic validation; bearer means access only. */
    public boolean validateToken(String token) {
        return validateAccessToken(token);
    }

    public boolean validateAccessToken(String token) {
        return validateForUse(token, "access");
    }

    public boolean validateRefreshToken(String token) {
        return validateForUse(token, "refresh");
    }

    private boolean validateForUse(String token, String expectedUse) {
        try {
            Claims claims = Jwts.parser().verifyWith(secretKey).build()
                    .parseSignedClaims(token).getPayload();
            String subject = claims.getSubject();
            if (claims.getExpiration() == null || subject == null || !subject.matches("[0-9]{1,19}")) return false;
            Long.parseLong(subject);
            // Inspect the verified raw payload: JJWT normalizes null custom claims
            // away, which must not turn an explicitly invalid type into legacy.
            JsonNode raw = CLAIMS_JSON.readTree(java.util.Base64.getUrlDecoder()
                    .decode(token.split("\\.", -1)[1]));
            boolean accessIdentity = raw.path("username").isTextual()
                    && raw.path("email").isTextual();
            boolean refreshIdentity = !raw.has("username") && !raw.has("email");
            if (raw.has("token_use")) {
                if (!raw.get("token_use").isTextual()
                        || !expectedUse.equals(raw.get("token_use").textValue())) return false;
            }
            // Existing Spring tokens have no type claim. Their signed payloads
            // distinguish access (username + email) from refresh (neither).
            // Never fall back when an explicit, unknown type is present.
            return expectedUse.equals("access") ? accessIdentity : refreshIdentity;
        } catch (JwtException | IllegalArgumentException | java.io.IOException e) {
            return false;
        }
    }

    public long getAccessTokenExpirationSeconds() {
        return accessTokenExpirationMs / 1000;
    }
}
