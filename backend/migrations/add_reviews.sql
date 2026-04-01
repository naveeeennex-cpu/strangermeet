-- Event/Trip reviews
CREATE TABLE IF NOT EXISTS event_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES community_events(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    review TEXT DEFAULT '',
    images TEXT[] DEFAULT '{}',
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(event_id, user_id)
);
