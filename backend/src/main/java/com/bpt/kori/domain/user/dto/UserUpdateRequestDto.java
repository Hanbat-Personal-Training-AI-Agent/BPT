package com.bpt.kori.domain.user.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Getter
@Setter
@NoArgsConstructor
@Schema(description = "사용자 프로필 수정 요청 DTO")
public class UserUpdateRequestDto {

    @Schema(description = "변경할 사용자 아이디", example = "new_username")
    private String username;

    @Schema(description = "변경할 이메일", example = "new_email@bpt.app")
    private String email;

    @Schema(description = "변경할 이름", example = "홍길동")
    private String name;

    @Schema(description = "전화번호", example = "010-1234-5678")
    private String phoneNumber;

    @Schema(description = "성별 (MALE, FEMALE, NOT_SPECIFIED)", example = "MALE")
    private String gender;

    @Schema(description = "생년월일 (YYYY-MM-DD)", example = "1998-05-15")
    private String birthDate;

    @Schema(description = "신장 (cm)", example = "178.5")
    private Double heightCm;

    @Schema(description = "체중 (kg)", example = "74.0")
    private Double weightKg;

    @Schema(description = "운동 목표", example = "근력 증량")
    private String workoutGoal;

    @Schema(description = "주간 목표 운동 횟수", example = "4")
    private Integer weeklyFrequency;

    @Schema(description = "알림 시간 (HH:mm)", example = "18:00")
    private String notificationTime;

    @Schema(description = "알림 활성화 여부", example = "true")
    private Boolean notificationEnabled;

    @Schema(description = "체형 분석 로컬 파일 경로", example = "/var/mobile/Containers/Data/Application/scan_01.dat")
    private String bodyScanLocalPath;
}
