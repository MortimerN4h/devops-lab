package lab.notes;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

// @SpringBootApplication = scan this package for @RestController, @Entity, repositories...
// and configure everything found on the classpath (Tomcat, Jackson, MySQL pool...) automatically.
@SpringBootApplication
public class NotesApplication {
    public static void main(String[] args) {
        SpringApplication.run(NotesApplication.class, args);
    }
}
