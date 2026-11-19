-- Runs once, when the pg-data volume is empty (see docker-compose.yml).
-- Unlike MongoDB, PostgreSQL needs the table (schema) to exist before inserting.

CREATE TABLE notes (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, -- auto-increment 1, 2, 3...
  text       VARCHAR(200) NOT NULL,
  done       BOOLEAN      NOT NULL DEFAULT FALSE,
  due_date   DATE,                                            -- NULL = no deadline
  created_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Same sample notes as the Node app; due dates relative to the day the seed runs.
INSERT INTO notes (text, done, due_date) VALUES
  ('Learn Docker',        TRUE,  CURRENT_DATE - 2),
  ('Learn Terraform',     FALSE, CURRENT_DATE),
  ('Deploy to AWS',       FALSE, CURRENT_DATE + 7),
  ('Read the Nginx docs', FALSE, NULL);
