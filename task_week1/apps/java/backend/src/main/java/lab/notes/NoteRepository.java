package lab.notes;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

// Spring Data writes the implementation at startup:
// - JpaRepository gives save(), findById(), existsById(), deleteById()...
// - findAllByOrderByIdDesc is generated FROM ITS NAME: SELECT ... ORDER BY id DESC
public interface NoteRepository extends JpaRepository<Note, Long> {
    List<Note> findAllByOrderByIdDesc();
}
