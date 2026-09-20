package com.bpt.kori.domain.user.dto;

import com.bpt.kori.domain.user.entity.User;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;

@Getter
@AllArgsConstructor
@Builder
public class UserDto {

    private final String id;
    private final String username;
    private final String name;
    private final String email;
    private final String password;
    private final String avatarInitials;
    private final String birthDate;
    private final double weightKg;
    private final double heightCm;
    private final String gender;
    private final String workoutGoal;
    private final int totalWorkouts;
    private final int streakDays;
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
                .birthDate(user.getBirthDate() != null ? user.getBirthDate().toString() : null)
                .weightKg(user.getWeightKg() != null ? user.getWeightKg().doubleValue() : 0.0)
                .heightCm(user.getHeightCm() != null ? user.getHeightCm().doubleValue() : 0.0)
                .gender(user.getGender())
                .workoutGoal(user.getWorkoutGoal())
                .totalWorkouts(user.getTotalWorkouts() != null ? user.getTotalWorkouts() : 0)
                .streakDays(user.getStreakDays() != null ? user.getStreakDays() : 0)
                .joinedAt(user.getCreatedAt() != null ? user.getCreatedAt().toString() : "")
                .build();
    }
}
