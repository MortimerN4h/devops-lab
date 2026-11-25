package lab.notes;

import jakarta.persistence.*;
import java.time.Instant;
import java.time.LocalDate;

// JPA entity: one object = one row of the "notes" table. Hibernate writes the SQL for us.
@Entity
@Table(name = "notes")
public class Note {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY) // MySQL AUTO_INCREMENT gives the id
    private Long id;

    @Column(nullable = false, length = 200)
    private String text;

    @Column(nullable = false)
    private boolean done;

    @Column(name = "due_date") // NULL = no deadline
    private LocalDate dueDate;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    protected Note() {} // JPA needs an empty constructor

    public Note(String text, boolean done, LocalDate dueDate, Instant createdAt) {
        this.text = text;
        this.done = done;
        this.dueDate = dueDate;
        this.createdAt = createdAt;
    }

    public Long getId() { return id; }
    public String getText() { return text; }
    public boolean isDone() { return done; }
    public LocalDate getDueDate() { return dueDate; }
    public Instant getCreatedAt() { return createdAt; }

    public void replace(String text, boolean done, LocalDate dueDate) { // PUT = full replace
        this.text = text;
        this.done = done;
        this.dueDate = dueDate;
    }
}
