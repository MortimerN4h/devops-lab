package lab.notes;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.time.temporal.ChronoUnit;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

// Notes API with Spring Boot + MySQL. Same contract as every other backend: ../../../API.md
@RestController
@RequestMapping("/api")
public class NoteController {
    private static final DateTimeFormatter CREATED_AT =
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSSX").withZone(ZoneOffset.UTC);

    private final NoteRepository notes;
    private final ObjectMapper json;

    // Constructor injection: Spring creates the repository and the JSON mapper and passes them in
    public NoteController(NoteRepository notes, ObjectMapper json) {
        this.notes = notes;
        this.json = json;
    }

    // ---- Routes ----

    @GetMapping("/health")
    Map<String, String> health() {
        return Map.of("status", "ok", "backend", "Java + Spring Boot + MySQL");
    }

    @GetMapping("/notes")
    List<Map<String, Object>> list() {
        return notes.findAllByOrderByIdDesc().stream().map(NoteController::toJson).toList();
    }

    @GetMapping("/notes/{id}")
    Map<String, Object> get(@PathVariable String id) {
        return toJson(find(id));
    }

    @PostMapping("/notes")
    ResponseEntity<Map<String, Object>> create(@RequestBody(required = false) String body) {
        Input in = validate(body);
        Instant now = Instant.now().truncatedTo(ChronoUnit.MILLIS); // DATETIME(3) keeps milliseconds
        Note saved = notes.save(new Note(in.text(), in.done(), in.dueDate(), now));
        return ResponseEntity.status(HttpStatus.CREATED).body(toJson(saved));
    }

    @PutMapping("/notes/{id}")
    @Transactional // the changes made to "note" are written to the DB when the method returns
    Map<String, Object> update(@PathVariable String id, @RequestBody(required = false) String body) {
        Note note = find(id);
        Input in = validate(body);
        note.replace(in.text(), in.done(), in.dueDate()); // full replace: missing dueDate -> NULL
        return toJson(note);
    }

    @DeleteMapping("/notes/{id}")
    ResponseEntity<Void> delete(@PathVariable String id) {
        notes.delete(find(id));
        return ResponseEntity.noContent().build(); // 204, no body
    }

    // ---- Helpers ----

    /** A malformed id ("does-not-exist") is treated as "not found", like every backend. */
    private Note find(String id) {
        if (!id.matches("[0-9]{1,18}")) {
            throw ApiError.notFound(id);
        }
        return notes.findById(Long.parseLong(id)).orElseThrow(() -> ApiError.notFound(id));
    }

    private record Input(String text, boolean done, LocalDate dueDate) {}

    // We read the body as a String ourselves (instead of a @RequestBody class + @Valid, the usual Spring way)
    // to return exactly the codes of API.md: INVALID_JSON vs VALIDATION_ERROR, "done must be a boolean"...
    private Input validate(String raw) {
        JsonNode body;
        try {
            body = json.readTree(raw == null ? "" : raw);
        } catch (Exception e) {
            body = null;
        }
        if (body == null || body.isMissingNode()) {
            throw new ApiError(HttpStatus.BAD_REQUEST, "INVALID_JSON", "Request body is not valid JSON");
        }
        JsonNode textNode = body.get("text"); // null when missing, or when the body is not an object
        String text = textNode != null && textNode.isTextual() ? textNode.asText().strip() : "";
        if (text.isEmpty()) {
            throw ApiError.invalid("text is required");
        }
        if (text.codePointCount(0, text.length()) > 200) { // characters, not UTF-16 units
            throw ApiError.invalid("text must be at most 200 characters");
        }
        JsonNode doneNode = body.get("done");
        if (doneNode != null && !doneNode.isBoolean()) {
            throw ApiError.invalid("done must be a boolean");
        }
        return new Input(text, doneNode != null && doneNode.asBoolean(), parseDueDate(body.get("dueDate")));
    }

    /** dueDate: missing/null -> null, otherwise a REAL date "YYYY-MM-DD" (2026-02-30 is rejected). */
    private static LocalDate parseDueDate(JsonNode node) {
        if (node == null || node.isNull()) {
            return null;
        }
        if (node.isTextual() && node.asText().matches("[0-9]{4}-[0-9]{2}-[0-9]{2}")) {
            try {
                return LocalDate.parse(node.asText()); // ISO format, STRICT: checks the calendar
            } catch (DateTimeParseException e) {
                // fall through
            }
        }
        throw ApiError.invalid("dueDate must be a date in YYYY-MM-DD format or null");
    }

    /** Entity -> API JSON (camelCase), same shape as API.md. LinkedHashMap keeps the field order. */
    private static Map<String, Object> toJson(Note n) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", n.getId());
        m.put("text", n.getText());
        m.put("done", n.isDone());
        m.put("dueDate", n.getDueDate() == null ? null : n.getDueDate().toString());
        m.put("createdAt", CREATED_AT.format(n.getCreatedAt()));
        return m;
    }
}
