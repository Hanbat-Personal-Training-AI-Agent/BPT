package com.bpt.kori.domain.user.controller;

import com.bpt.kori.domain.user.dto.DashboardSummaryResponseDto;
import com.bpt.kori.domain.user.dto.OnboardingRequest;
import com.bpt.kori.domain.user.dto.OnboardingResponse;
import com.bpt.kori.domain.user.dto.UserDto;
import com.bpt.kori.domain.user.service.UserService;
import com.bpt.kori.security.UserPrincipal;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/users")
@RequiredArgsConstructor
public class UserController {

    private final UserService userService;

    @GetMapping("/me")
    public ResponseEntity<UserDto> getMyProfile(@AuthenticationPrincipal UserPrincipal userPrincipal) {
        UserDto profile = userService.getProfile(userPrincipal.getUserId());
        return ResponseEntity.ok(profile);
    }

    @PutMapping("/me")
    public ResponseEntity<UserDto> updateMyProfile(
            @AuthenticationPrincipal UserPrincipal userPrincipal,
            @RequestBody UserDto request
    ) {
        UserDto updated = userService.updateProfile(userPrincipal.getUserId(), request);
        return ResponseEntity.ok(updated);
    }

    @PutMapping("/me/onboarding")
    public ResponseEntity<OnboardingResponse> updateOnboarding(
            @AuthenticationPrincipal UserPrincipal userPrincipal,
            @RequestBody OnboardingRequest request
    ) {
        OnboardingResponse response = userService.updateOnboarding(userPrincipal.getUserId(), request);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/me/dashboard")
    public ResponseEntity<DashboardSummaryResponseDto> getDashboardSummary(@AuthenticationPrincipal UserPrincipal userPrincipal) {
        DashboardSummaryResponseDto response = userService.getDashboardSummary(userPrincipal.getUserId());
        return ResponseEntity.ok(response);
    }
}
