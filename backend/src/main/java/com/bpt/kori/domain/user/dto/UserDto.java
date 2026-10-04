package com.bpt.kori.domain.user.dto;

import com.bpt.kori.domain.user.entity.User;
import io.swagger.v3.oas.annotations.media.Schema;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;

@Getter
@AllArgsConstructor
@Builder
@Schema(description = "사용자 상세 프로필 응답 DTO")
public class UserDto {

    @Schema(description = "사용자 고유 ID", example = "1")
    private final String id;

    @Schema(description = "사용자 아이디", example = "jihoon_kim")
    private final String username;

    @Schema(description = "이름", example = "지훈")
    private final String name;

    @Schema(description = "이메일", example = "jihoon@bpt.app")
    private final String email;

    @Schema(description = "비밀번호 (보안상 빈 문자열)", example = "")
    private final String password;

    @Schema(description = "아바타 이니셜", example = "지")
    private final String avatarInitials;

    @Schema(description = "전화번호", example = "010-1234-5678")
    private final String phoneNumber;

    @Schema(description = "생년월일 (YYYY-MM-DD)", example = "1998-05-15")
    private final String birthDate;

    @Schema(description = "체중 (kg)", example = "74.0")
    private final double weightKg;

    @Schema(description = "신장 (cm)", example = "178.5")
    private final double heightCm;

    @Schema(description = "성별 (MALE, FEMALE, NOT_SPECIFIED)", example = "MALE")
    private final String gender;

    @Schema(description = "운동 목표", example = "근력 증량")
    private final String workoutGoal;

    @Schema(description = "주간 목표 운동 횟수", example = "4")
    private final Integer weeklyFrequency;

    @Schema(description = "푸시 알림 시간 (HH:mm)", example = "18:00")
    private final String notificationTime;

    @Schema(description = "마지막 체형 측정일 (YYYY-MM-DD)", example = "2026-09-30")
    private final String lastBodyScanDate;

    @Schema(description = "누적 운동 횟수", example = "12")
    private final int totalWorkouts;

    @Schema(description = "연속 운동 일수", example = "3")
    private final int streakDays;

    @Schema(description = "가입 일시", example = "2026-09-30T16:30:00")
    private final String joinedAt;

    public static UserDto fromEntity(User user) {
        String effectiveName = (user.getName() != null && !user.getName().isBlank())
                ? user.getName()
                : (user.getUsername() != null ? user.getUsername() : user.getEmail().split("@")[0]);
        String initials = effectiveName.substring(0, 1).toUpperCase();

        return UserDto.builder()
                .id(String.valueOf(user.getId()))
                .username(user.getUsername())
                .name(effectiveName)
                .email(user.getEmail())
                .password("")
                .avatarInitials(initials)
                .phoneNumber(user.getPhoneNumber())
                .birthDate(user.getBirthDate() != null ? user.getBirthDate().toString() : null)
                .weightKg(user.getWeightKg() != null ? user.getWeightKg().doubleValue() : 0.0)
                .heightCm(user.getHeightCm() != null ? user.getHeightCm().doubleValue() : 0.0)
                .gender(user.getGender())
                .workoutGoal(user.getWorkoutGoal())
                .weeklyFrequency(user.getWeeklyFrequency() != null ? user.getWeeklyFrequency() : 3)
                .notificationTime(user.getNotificationTime())
                .lastBodyScanDate(user.getLastBodyScanDate() != null ? user.getLastBodyScanDate().toString() : null)
                .totalWorkouts(user.getTotalWorkouts() != null ? user.getTotalWorkouts() : 0)
                .streakDays(user.getStreakDays() != null ? user.getStreakDays() : 0)
                .joinedAt(user.getCreatedAt() != null ? user.getCreatedAt().toString() : "")
                .build();
    }
}
