ALTER TABLE users ADD COLUMN IF NOT EXISTS username VARCHAR(30) UNIQUE;
-- Generate default usernames for existing users based on their name
UPDATE users SET username = LOWER(REPLACE(REPLACE(name, ' ', '_'), '.', '')) || '_' || SUBSTRING(id::text, 1, 4) WHERE username IS NULL;
