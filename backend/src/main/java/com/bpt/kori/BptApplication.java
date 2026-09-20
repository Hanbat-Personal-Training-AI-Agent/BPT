package com.bpt.kori;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.data.jpa.repository.config.EnableJpaAuditing;

@SpringBootApplication
@EnableJpaAuditing
public class BptApplication {

    public static void main(String[] args) {
        SpringApplication.run(BptApplication.class, args);
    }
}
