-- Runs once, when the mysql-data volume is empty (see docker-compose.yml).
-- The image already created the database "notesdb" and the user "notes" (MYSQL_* variables) and runs this inside notesdb.

CREATE TABLE notes (
  id         BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,  -- MySQL's auto-increment 1, 2, 3...
  text       VARCHAR(200) NOT NULL,
  done       BOOLEAN      NOT NULL DEFAULT FALSE,               -- MySQL stores BOOLEAN as TINYINT(1): 0/1
  due_date   DATE         NULL,                                 -- NULL = no deadline
  created_at DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) -- (3) = keep milliseconds; stored in UTC
) CHARACTER SET utf8mb4;                                        -- utf8mb4 = full Unicode (Vietnamese, emoji)

-- Same sample notes as the other apps; due dates relative to the day the seed runs.
INSERT INTO notes (text, done, due_date) VALUES
  ('Learn Docker',        TRUE,  CURDATE() - INTERVAL 2 DAY),
  ('Learn Terraform',     FALSE, CURDATE()),
  ('Deploy to AWS',       FALSE, CURDATE() + INTERVAL 7 DAY),
  ('Read the Nginx docs', FALSE, NULL);
