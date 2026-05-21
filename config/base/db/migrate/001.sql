-- migrate-001: expand password/hash field length to 256 for argon2id + pepper prefix support
ALTER TABLE users DROP CONSTRAINT users_password_len;
ALTER TABLE users ADD CONSTRAINT users_password_len CHECK (char_length(password) <= 256);

ALTER TABLE password DROP CONSTRAINT password_hash_len;
ALTER TABLE password ADD CONSTRAINT password_hash_len CHECK (char_length(hash) <= 256);
