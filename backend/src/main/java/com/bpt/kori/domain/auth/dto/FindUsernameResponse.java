package com.bpt.kori.domain.auth.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Schema(description = "아이디 찾기 응답 DTO")
public class FindUsernameResponse {

    @Schema(description = "조회 성공 여부", example = "true")
    private boolean success;

    @Schema(description = "마스킹된 아이디", example = "qwe***")
    private String maskedUsername;

    @Schema(description = "전체 아이디 (클라이언트 필요 시 사용)", example = "qwer123")
    private String username;

    @Schema(description = "결과 메시지", example = "아이디 조회가 완료되었습니다.")
    private String message;
}
