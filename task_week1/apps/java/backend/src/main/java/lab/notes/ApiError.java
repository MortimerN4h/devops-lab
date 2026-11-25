package lab.notes;

import org.springframework.http.HttpStatus;

// An expected error with its HTTP status and API.md code; turned into JSON by ApiExceptionHandler.
public class ApiError extends RuntimeException {
    final HttpStatus status;
    final String code;

    ApiError(HttpStatus status, String code, String message) {
        super(message);
        this.status = status;
        this.code = code;
    }

    static ApiError notFound(String id) {
        return new ApiError(HttpStatus.NOT_FOUND, "NOT_FOUND", "Note " + id + " not found");
    }

    static ApiError invalid(String message) {
        return new ApiError(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", message);
    }
}
