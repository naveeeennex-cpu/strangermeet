-- Sub group messages
ALTER TABLE sub_group_messages ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN DEFAULT false;
ALTER TABLE sub_group_messages ADD COLUMN IF NOT EXISTS deleted_by VARCHAR(255);
ALTER TABLE sub_group_messages ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false;
ALTER TABLE sub_group_messages ADD COLUMN IF NOT EXISTS message_type VARCHAR(50) DEFAULT 'text';
-- message_type can be: text, image, video, poll, location, deleted

-- Community messages
ALTER TABLE community_messages ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN DEFAULT false;
ALTER TABLE community_messages ADD COLUMN IF NOT EXISTS deleted_by VARCHAR(255);
ALTER TABLE community_messages ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false;

-- DM messages
ALTER TABLE messages ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN DEFAULT false;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS deleted_by VARCHAR(255);

-- Polls table
CREATE TABLE IF NOT EXISTS chat_polls (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sub_group_id UUID REFERENCES sub_groups(id) ON DELETE CASCADE,
    community_id UUID,
    created_by UUID NOT NULL REFERENCES users(id),
    question TEXT NOT NULL,
    options JSONB NOT NULL DEFAULT '[]',
    is_anonymous BOOLEAN DEFAULT false,
    is_multiple_choice BOOLEAN DEFAULT false,
    expires_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Poll votes
CREATE TABLE IF NOT EXISTS chat_poll_votes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    poll_id UUID NOT NULL REFERENCES chat_polls(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id),
    option_index INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(poll_id, user_id, option_index)
);
