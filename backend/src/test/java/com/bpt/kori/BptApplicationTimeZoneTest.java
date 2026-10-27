package com.bpt.kori;

import com.bpt.kori.domain.user.entity.User;
import com.bpt.kori.domain.user.repository.UserCalibrationRepository;
import com.bpt.kori.domain.user.repository.UserRepository;
import com.bpt.kori.domain.user.service.UserService;
import com.bpt.kori.domain.workout.repository.WorkoutRecordRepository;
import com.bpt.kori.domain.workout.service.WorkoutService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.parallel.ResourceLock;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.mockito.MockedStatic;
import org.springframework.boot.SpringApplication;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.Optional;
import java.util.TimeZone;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

@ResourceLock("java.util.TimeZone.default")
class BptApplicationTimeZoneTest {
    @Test
    void main_setsSeoulTimeZoneBeforeSpringStarts() {
        TimeZone previous = TimeZone.getDefault();
        TimeZone.setDefault(TimeZone.getTimeZone("UTC"));
        String[] args = new String[0];
        try (MockedStatic<SpringApplication> spring = mockStatic(SpringApplication.class)) {
            spring.when(() -> SpringApplication.run(BptApplication.class, args)).thenAnswer(invocation -> {
                assertThat(ZoneId.systemDefault()).isEqualTo(ZoneId.of("Asia/Seoul"));
                return null;
            });
            BptApplication.main(args);
            spring.verify(() -> SpringApplication.run(BptApplication.class, args));
        } finally {
            TimeZone.setDefault(previous);
        }
    }

    @ParameterizedTest
    @CsvSource({
            "2026-10-31T15:30:00Z, 2026-11-01, 2026-10-26, 2026-11-01",
            "2026-11-01T15:30:00Z, 2026-11-02, 2026-11-02, 2026-11-08"
    })
    void dashboardAndDefaultCalendar_useKoreanDateAtUtcBoundaries(
            String instantText, String expectedDate, String mondayText, String sundayText) {
        Instant instant = Instant.parse(instantText);
        LocalDate monday = LocalDate.parse(mondayText);
        LocalDate sunday = LocalDate.parse(sundayText);
        LocalDate today = LocalDate.parse(expectedDate);
        TimeZone previous = TimeZone.getDefault();
        TimeZone.setDefault(TimeZone.getTimeZone("UTC"));
        // Stub only the wall clock, preserving LocalDate's zone conversion behavior.
        try (MockedStatic<SpringApplication> spring = mockStatic(SpringApplication.class);
             MockedStatic<LocalDate> dates = mockStatic(LocalDate.class, CALLS_REAL_METHODS)) {
            dates.when(LocalDate::now).thenAnswer(invocation ->
                    LocalDate.now(Clock.fixed(instant, ZoneId.systemDefault())));
            BptApplication.main(new String[0]);
            UserRepository users = mock(UserRepository.class);
            WorkoutRecordRepository workouts = mock(WorkoutRecordRepository.class);
            UserCalibrationRepository calibrations = mock(UserCalibrationRepository.class);
            when(users.findById(1L)).thenReturn(Optional.of(
                    User.builder().id(1L).username("tester").build()));

            var dashboard = new UserService(users, workouts, calibrations).getDashboardSummary(1L);
            var calendar = new WorkoutService(workouts, users, new ObjectMapper())
                    .getMonthlyCalendar(1L, null, null);

            assertThat(dashboard.getDate()).isEqualTo(expectedDate);
            verify(workouts).findAllByUserIdAndDateBetweenOrderByDateAsc(
                    1L, today.atStartOfDay(), today.atTime(LocalTime.MAX));
            verify(workouts).findAllByUserIdAndDateBetweenOrderByDateAsc(
                    1L, monday.atStartOfDay(), sunday.atTime(LocalTime.MAX));
            assertThat(calendar.getYear()).isEqualTo(2026);
            assertThat(calendar.getMonth()).isEqualTo(11);
            verify(workouts).findAllByUserIdAndDateBetweenOrderByDateAsc(1L,
                    LocalDate.of(2026, 11, 1).atStartOfDay(), LocalDate.of(2026, 11, 30).atTime(23, 59, 59));
        } finally {
            TimeZone.setDefault(previous);
        }
    }
}
