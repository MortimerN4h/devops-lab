package lab.notes;

import java.util.LinkedHashMap;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.resource.NoResourceFoundException;
import jakarta.servlet.http.HttpServletRequest;

// @RestControllerAdvice = applies to every controller: every failure becomes {"error": {"code", "message"}}
@RestControllerAdvice
public class ApiExceptionHandler {
    private static final Logger log = LoggerFactory.getLogger(ApiExceptionHandler.class);

    static ResponseEntity<Map<String, Object>> body(HttpStatus status, String code, String message) {
        Map<String, Object> error = new LinkedHashMap<>(); // keeps "code" before "message" like the other backends
        error.put("code", code);
        error.put("message", message);
        return ResponseEntity.status(status).body(Map.of("error", error));
    }

    @ExceptionHandler(ApiError.class)
    ResponseEntity<Map<String, Object>> api(ApiError e) {
        return body(e.status, e.code, e.getMessage());
    }

    // Unknown route (Spring looks for a static file and finds none) or wrong method: 404 like the other backends
    @ExceptionHandler({NoResourceFoundException.class, HttpRequestMethodNotSupportedException.class})
    ResponseEntity<Map<String, Object>> noRoute(HttpServletRequest req) {
        return body(HttpStatus.NOT_FOUND, "NOT_FOUND", "Route " + req.getRequestURI() + " not found");
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<Map<String, Object>> unexpected(Exception e) {
        log.error("Unexpected error", e); // full stack trace in the logs, never to the client
        return body(HttpStatus.INTERNAL_SERVER_ERROR, "INTERNAL_ERROR", "Unexpected server error");
    }
}
