package com.bpt.kori.domain.workout.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;

import java.time.LocalDateTime;

@Getter
@AllArgsConstructor
@Builder
@Schema(description = "운동 메타데이터 동기화 응답 DTO")
public class WorkoutMetadataResponseDto {

    @Schema(description = "서버 생성 레코드 ID", example = "101")
    private final String serverRecordId;

    @Schema(description = "클라이언트 레코드 ID", example = "550e8400-e29b-41d4-a716-446655440000")
    private final String clientRecordId;

    @Schema(description = "녹화 영상 로컬 경로", example = "/var/mobile/Containers/Data/Application/workout_rec_01.mp4")
    private final String videoLocalPath;

    @Schema(description = "동기화 성공 여부", example = "true")
    private final boolean success;

    @Schema(description = "결과 메시지", example = "Record synced successfully")
    private final String message;

    @Schema(description = "동기화 일시", example = "2026-09-30T16:00:05")
    private final LocalDateTime syncedAt;
}
