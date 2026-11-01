package com.bpt.kori.domain.workout;

import com.bpt.kori.domain.user.entity.User;
import com.bpt.kori.domain.user.repository.UserRepository;
import com.bpt.kori.domain.workout.repository.WorkoutRecordRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.core.env.Environment;
import org.springframework.http.*;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.nio.file.Path;
import java.time.LocalDate;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verifyNoInteractions;

/** Opt-in ONLY to the root-owned disposable database. Never uses application datasource defaults. */
@EnabledIfEnvironmentVariable(named = "BPT_TEST_JDBC_URL", matches = ".+")
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {"server.address=127.0.0.1", "spring.config.import=",
                "spring.jpa.hibernate.ddl-auto=create-drop", "spring.jpa.show-sql=false",
                "spring.jpa.properties.hibernate.show_sql=false", "logging.level.org.hibernate.SQL=WARN"})
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
class WorkoutHttpPostgresContractTest {
    private static final String URL = "jdbc:postgresql://127.0.0.1:51066/bpt_contract";
    private static final String USER = "bpt_contract";
    private static final String PASSWORD = "bpt_contract_only_not_a_user_account";
    private static final String ACCOUNT_PASSWORD = "SyntheticContractOnly-20261102!";

    private static String requireExact(String name, String expected) {
        String value = System.getenv(name);
        if (!expected.equals(value)) throw new IllegalStateException("Refusing non-disposable test target: " + name);
        return value;
    }

    @DynamicPropertySource
    static void disposableProperties(DynamicPropertyRegistry registry) {
        // Validate everything before registering any datasource property / constructing the context.
        String url = requireExact("BPT_TEST_JDBC_URL", URL);
        String user = requireExact("BPT_TEST_JDBC_USER", USER);
        String password = requireExact("BPT_TEST_JDBC_PASSWORD", PASSWORD);
        registry.add("spring.datasource.url", () -> url);
        registry.add("spring.datasource.username", () -> user);
        registry.add("spring.datasource.password", () -> password);
        registry.add("spring.datasource.hikari.maximum-pool-size", () -> 2);
        registry.add("spring.datasource.hikari.minimum-idle", () -> 0);
        registry.add("spring.datasource.hikari.connection-timeout", () -> 3000);
        registry.add("spring.datasource.hikari.initialization-fail-timeout", () -> 3000);
        registry.add("jwt.secret", () -> java.util.Base64.getEncoder().encodeToString(
                "synthetic-local-contract-only-20261102-never-a-real-user-token-secret".getBytes(java.nio.charset.StandardCharsets.UTF_8)));
        registry.add("spring.mail.host", () -> "127.0.0.1");
        registry.add("spring.mail.port", () -> 1);
        registry.add("spring.mail.username", () -> "synthetic-test-only");
        registry.add("spring.mail.password", () -> "synthetic-test-only");
    }

    @LocalServerPort int port;
    @Autowired TestRestTemplate http;
    @Autowired ObjectMapper json;
    @Autowired UserRepository users;
    @Autowired WorkoutRecordRepository records;
    @Autowired PasswordEncoder passwords;
    @Autowired PlatformTransactionManager transactions;
    @Autowired EntityManager entityManager;
    @Autowired Environment environment;
    @MockBean JavaMailSender mail;

    private String endpoint(String path) { return "http://127.0.0.1:" + port + "/api/v1" + path; }
    private HttpEntity<Object> authenticated(String token, Object body) {
        HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(token);
        headers.setContentType(MediaType.APPLICATION_JSON);
        return new HttpEntity<>(body, headers);
    }
    private String login(String username) {
        var response = http.postForEntity(endpoint("/auth/login"),
                Map.of("username", username, "password", ACCOUNT_PASSWORD), JsonNode.class);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isNotNull();
        String token = response.getBody().path("accessToken").asText();
        assertThat(token).isNotBlank();
        return token;
    }

    @Test void realLoginHttpSecurityPersistenceAndFreshJsonRoundTrip() throws Exception {
        assertThat(environment.getProperty("spring.datasource.url")).isEqualTo(URL);
        assertThat(environment.getProperty("server.address")).isEqualTo("127.0.0.1");
        var owner = users.saveAndFlush(User.builder().username("contract_a").email("contract_a@local.invalid")
                .password(passwords.encode(ACCOUNT_PASSWORD)).build());
        users.saveAndFlush(User.builder().username("contract_b").email("contract_b@local.invalid")
                .password(passwords.encode(ACCOUNT_PASSWORD)).build());
        String tokenA = login("contract_a"), tokenB = login("contract_b");
        ObjectNode request = (ObjectNode) json.readTree(Path.of("../test/fixtures/workout_evidence_v1_request.json").toFile());
        request.put("clientRecordId", "pg-native-a");
        request.put("targetSets", 3);
        request.put("date", LocalDate.now() + "T12:00:00");
        assertThat(records.count()).isZero();

        var saved = http.exchange(endpoint("/workouts/records"), HttpMethod.POST, authenticated(tokenA, request), JsonNode.class);
        assertThat(saved.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(saved.getBody().path("success").asBoolean()).isTrue();
        String serverId = saved.getBody().path("serverRecordId").asText();
        assertThat(serverId).isNotBlank();

        // A separate transaction after the HTTP transaction has committed; clear first-level cache.
        new TransactionTemplate(transactions).executeWithoutResult(status -> {
            entityManager.clear();
            var stored = records.findByClientRecordId("pg-native-a").orElseThrow();
            assertThat(stored.getUser().getId()).isEqualTo(owner.getId());
            assertThat(stored.getCorrectReps()).isZero();
            assertThat(stored.getIncorrectReps()).isZero();
            assertThat(stored.getSetRecords()).hasSize(1);
            assertThat(stored.getTargetSets()).isEqualTo(3);
            assertThat(stored.getTotalSets()).isEqualTo(1);
            try { assertThat(json.readTree(stored.getPoseMetricsSummary())).isEqualTo(request.get("poseMetricsSummary")); }
            catch (Exception error) { throw new AssertionError(error); }
        });

        var fresh = http.exchange(endpoint("/workouts/records"), HttpMethod.GET, authenticated(tokenA, null), JsonNode.class);
        assertThat(fresh.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(fresh.getBody().size()).isEqualTo(1);
        var row = fresh.getBody().get(0);
        assertThat(row.get("poseMetricsSummary")).isEqualTo(request.get("poseMetricsSummary"));
        assertThat(row.path("totalReps").asInt()).isEqualTo(1);
        assertThat(row.path("correctReps").asInt()).isZero();
        assertThat(row.path("incorrectReps").asInt()).isZero();
        assertThat(row.path("totalSets").asInt()).isEqualTo(1);
        assertThat(row.path("targetSets").asInt()).isEqualTo(3);
        assertThat(row.path("poseMetricsSummary").path("workoutEvidence").get("postureScore").isNull()).isTrue();

        var retry = http.exchange(endpoint("/workouts/records/sync"), HttpMethod.POST, authenticated(tokenA, request), JsonNode.class);
        assertThat(retry.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(retry.getBody().path("serverRecordId").asText()).isEqualTo(serverId);
        assertThat(records.count()).isEqualTo(1);
        var otherList = http.exchange(endpoint("/workouts/records"), HttpMethod.GET, authenticated(tokenB, null), JsonNode.class);
        assertThat(otherList.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(otherList.getBody().size()).isZero();
        var collision = http.exchange(endpoint("/workouts/records/sync"), HttpMethod.POST, authenticated(tokenB, request), JsonNode.class);
        assertThat(collision.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(records.count()).isEqualTo(1);

        ObjectNode malformed = request.deepCopy();
        malformed.put("clientRecordId", "pg-malformed");
        ((ObjectNode) malformed.path("poseMetricsSummary").path("workoutEvidence")).put("completedReps", 999);
        var rejected = http.exchange(endpoint("/workouts/records"), HttpMethod.POST, authenticated(tokenA, malformed), JsonNode.class);
        assertThat(rejected.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(records.findByClientRecordId("pg-malformed")).isEmpty();
        assertThat(records.count()).isEqualTo(1);
        var dashboard = http.exchange(endpoint("/users/me/dashboard"), HttpMethod.GET, authenticated(tokenA, null), JsonNode.class);
        assertThat(dashboard.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(dashboard.getBody().path("completedSetsEvidenceVersion").asInt()).isEqualTo(1);
        assertThat(dashboard.getBody().path("todayCompletedSets").asInt()).isEqualTo(1);
        ObjectNode legacy = request.deepCopy();
        legacy.put("clientRecordId", "pg-legacy-a");
        legacy.putNull("poseMetricsSummary");
        legacy.put("correctReps", 1); legacy.put("incorrectReps", 0);
        legacy.put("totalSets", 9); // Legacy claimed total is not observation evidence.
        var legacySaved = http.exchange(endpoint("/workouts/records"), HttpMethod.POST, authenticated(tokenA, legacy), JsonNode.class);
        assertThat(legacySaved.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        var withLegacy = http.exchange(endpoint("/workouts/records"), HttpMethod.GET, authenticated(tokenA, null), JsonNode.class);
        JsonNode legacyRow = null;
        for (JsonNode item : withLegacy.getBody()) if ("pg-legacy-a".equals(item.path("clientRecordId").asText())) legacyRow = item;
        assertThat(legacyRow).isNotNull();
        assertThat(legacyRow.path("correctReps").asInt()).isEqualTo(1); // Preserve raw historical contract.
        assertThat(legacyRow.get("poseMetricsSummary").isNull()).isTrue(); // No manufactured assessment envelope.
        var mixedDashboard = http.exchange(endpoint("/users/me/dashboard"), HttpMethod.GET, authenticated(tokenA, null), JsonNode.class);
        assertThat(mixedDashboard.getBody().get("todayCompletedSets").isNull()).isTrue();
        assertThat(mixedDashboard.getBody().path("completedSetsEvidenceVersion").asInt()).isEqualTo(1);
        verifyNoInteractions(mail);
        // Distinct from the Mockito/Jackson fixture: this body crossed real HTTP and PostgreSQL.
        Path output = Path.of("build/contract-fixtures/workout-evidence-v1-postgres-response.json");
        java.nio.file.Files.createDirectories(output.getParent());
        json.writerWithDefaultPrettyPrinter().writeValue(output.toFile(), row);
    }
}
