-- Migration: Add video support to posts and stories
-- Run this if the tables already exist and need the new columns

ALTER TABLE posts ADD COLUMN IF NOT EXISTS media_type VARCHAR(10) DEFAULT 'image';
ALTER TABLE posts ADD COLUMN IF NOT EXISTS video_url TEXT DEFAULT '';
ALTER TABLE stories ADD COLUMN IF NOT EXISTS media_type VARCHAR(10) DEFAULT 'image';
ALTER TABLE stories ADD COLUMN IF NOT EXISTS video_url TEXT DEFAULT '';
