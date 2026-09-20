package com.bpt.kori.domain.auth.dto;

import lombok.AllArgsConstructor;
import lombok.Getter;

@Getter
@AllArgsConstructor
public class CheckUsernameResponse {

    private final boolean isAvailable;
    private final String message;
}
