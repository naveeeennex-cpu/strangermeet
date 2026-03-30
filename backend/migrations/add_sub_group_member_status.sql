-- Add status column to sub_group_members table
-- Supports: 'active' (default for existing and public group joins), 'pending' (for private group join requests), 'rejected'
-- This column is required for the private group join-request flow.
ALTER TABLE sub_group_members ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'active';
