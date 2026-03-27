# =====================================================================
# MIGRATION SQL (run manually if tables already exist):
#
# ALTER TABLE messages ADD COLUMN IF NOT EXISTS is_read BOOLEAN DEFAULT FALSE;
#
# NOTE: community_messages and sub_group_messages do NOT need is_read
# because read receipts are only supported for DMs (1-to-1 chats).
# The messages table was created with is_read already, so this ALTER
# is only needed if you created the table before is_read was added.
#
# -- Trip/Trek fields for community_events:
# ALTER TABLE community_events ADD COLUMN IF NOT EXISTS event_type TEXT DEFAULT 'event';
# ALTER TABLE community_events ADD COLUMN IF NOT EXISTS duration_days INTEGER DEFAULT 1;
# ALTER TABLE community_events ADD COLUMN IF NOT EXISTS difficulty TEXT DEFAULT 'easy';
# ALTER TABLE community_events ADD COLUMN IF NOT EXISTS includes TEXT[] DEFAULT '{}';
# ALTER TABLE community_events ADD COLUMN IF NOT EXISTS excludes TEXT[] DEFAULT '{}';
# ALTER TABLE community_events ADD COLUMN IF NOT EXISTS meeting_point TEXT DEFAULT '';
# ALTER TABLE community_events ADD COLUMN IF NOT EXISTS end_date TIMESTAMP;
# ALTER TABLE community_events ADD COLUMN IF NOT EXISTS max_altitude_m FLOAT DEFAULT 0;
# ALTER TABLE community_events ADD COLUMN IF NOT EXISTS total_distance_km FLOAT DEFAULT 0;
# =====================================================================

import asyncpg
from config import settings

pool: asyncpg.Pool = None


async def create_pool():
    global pool
    pool = await asyncpg.create_pool(
        dsn=settings.DATABASE_URL,
        min_size=2,
        max_size=10,
        statement_cache_size=0,
    )
    await init_db()


async def close_pool():
    global pool
    if pool:
        await pool.close()


def get_db() -> asyncpg.Pool:
    return pool


async def init_db():
    async with pool.acquire() as conn:
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                name VARCHAR(100) NOT NULL,
                email VARCHAR(255) UNIQUE NOT NULL,
                password_hash VARCHAR(255) NOT NULL,
                bio TEXT DEFAULT '',
                interests TEXT[] DEFAULT '{}',
                phone VARCHAR(20) DEFAULT '',
                profile_image_url TEXT DEFAULT '',
                created_at TIMESTAMP DEFAULT NOW()
            );
        """)

        # Add phone column if not exists (for existing tables)
        await conn.execute("""
            DO $$ BEGIN
                ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(20) DEFAULT '';
            EXCEPTION WHEN duplicate_column THEN NULL;
            END $$;
        """)

        # Add role column if not exists
        await conn.execute("""
            DO $$ BEGIN
                ALTER TABLE users ADD COLUMN IF NOT EXISTS role VARCHAR(20) DEFAULT 'customer';
            EXCEPTION WHEN duplicate_column THEN NULL;
            END $$;
        """)

        # Add cover_image_url column if not exists
        await conn.execute("""
            DO $$ BEGIN
                ALTER TABLE users ADD COLUMN IF NOT EXISTS cover_image_url TEXT DEFAULT '';
            EXCEPTION WHEN duplicate_column THEN NULL;
            END $$;
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS posts (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                image_url TEXT DEFAULT '',
                caption TEXT DEFAULT '',
                likes_count INTEGER DEFAULT 0,
                created_at TIMESTAMP DEFAULT NOW()
            );
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS post_likes (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
                user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                created_at TIMESTAMP DEFAULT NOW(),
                UNIQUE(post_id, user_id)
            );
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS comments (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
                user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                text TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT NOW()
            );
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS comment_likes (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                comment_id UUID NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                created_at TIMESTAMP DEFAULT NOW(),
                UNIQUE(comment_id, user_id)
            );
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS comment_replies (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                comment_id UUID NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                text TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT NOW()
            );
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS events (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                title VARCHAR(255) NOT NULL,
                description TEXT DEFAULT '',
                location VARCHAR(255) DEFAULT '',
                date TIMESTAMP NOT NULL,
                price FLOAT DEFAULT 0,
                slots INTEGER DEFAULT 0,
                image_url TEXT DEFAULT '',
                created_by UUID REFERENCES users(id),
                created_at TIMESTAMP DEFAULT NOW()
            );
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS bookings (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                event_id UUID REFERENCES events(id) ON DELETE CASCADE,
                payment_status VARCHAR(50) DEFAULT 'pending',
                payment_id VARCHAR(255) DEFAULT '',
                created_at TIMESTAMP DEFAULT NOW(),
                UNIQUE(user_id, event_id)
            );
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS messages (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                sender_id UUID REFERENCES users(id) ON DELETE CASCADE,
                receiver_id UUID REFERENCES users(id) ON DELETE CASCADE,
                message TEXT NOT NULL,
                is_read BOOLEAN DEFAULT FALSE,
                timestamp TIMESTAMP DEFAULT NOW()
            );
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS stories (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                image_url TEXT NOT NULL,
                caption TEXT DEFAULT '',
                created_at TIMESTAMP DEFAULT NOW(),
                expires_at TIMESTAMP DEFAULT NOW() + INTERVAL '24 hours'
            );
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS story_views (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                story_id UUID REFERENCES stories(id) ON DELETE CASCADE,
                user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                viewed_at TIMESTAMP DEFAULT NOW(),
                UNIQUE(story_id, user_id)
            );
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS story_replies (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                story_id UUID REFERENCES stories(id) ON DELETE CASCADE,
                user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                message TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT NOW()
            );
        """)

        # Friendships
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS friendships (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                requester_id UUID REFERENCES users(id) ON DELETE CASCADE,
                addressee_id UUID REFERENCES users(id) ON DELETE CASCADE,
                status VARCHAR(20) DEFAULT 'pending',
                created_at TIMESTAMP DEFAULT NOW(),
                updated_at TIMESTAMP DEFAULT NOW(),
                UNIQUE(requester_id, addressee_id)
            );
        """)

        # Communities
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS communities (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                name VARCHAR(255) NOT NULL,
                description TEXT DEFAULT '',
                image_url TEXT DEFAULT '',
                category VARCHAR(100) DEFAULT '',
                is_private BOOLEAN DEFAULT FALSE,
                created_by UUID REFERENCES users(id) ON DELETE CASCADE,
                members_count INTEGER DEFAULT 0,
                created_at TIMESTAMP DEFAULT NOW()
            );
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS community_members (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                community_id UUID REFERENCES communities(id) ON DELETE CASCADE,
                user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                role VARCHAR(20) DEFAULT 'member',
                status VARCHAR(20) DEFAULT 'active',
                joined_at TIMESTAMP DEFAULT NOW(),
                UNIQUE(community_id, user_id)
            );
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS community_posts (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                community_id UUID REFERENCES communities(id) ON DELETE CASCADE,
                user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                image_url TEXT DEFAULT '',
                caption TEXT DEFAULT '',
                likes_count INTEGER DEFAULT 0,
                created_at TIMESTAMP DEFAULT NOW()
            );
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS community_post_likes (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                post_id UUID REFERENCES community_posts(id) ON DELETE CASCADE,
                user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                created_at TIMESTAMP DEFAULT NOW(),
                UNIQUE(post_id, user_id)
            );
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS community_post_comments (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                post_id UUID REFERENCES community_posts(id) ON DELETE CASCADE,
                user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                text TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT NOW()
            );
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS community_messages (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                community_id UUID REFERENCES communities(id) ON DELETE CASCADE,
                user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                message TEXT NOT NULL,
                timestamp TIMESTAMP DEFAULT NOW()
            );
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS sub_groups (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                community_id UUID REFERENCES communities(id) ON DELETE CASCADE,
                name VARCHAR(255) NOT NULL,
                description TEXT DEFAULT '',
                type VARCHAR(50) DEFAULT 'general',
                created_by UUID REFERENCES users(id) ON DELETE CASCADE,
                created_at TIMESTAMP DEFAULT NOW()
            );
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS sub_group_members (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                sub_group_id UUID REFERENCES sub_groups(id) ON DELETE CASCADE,
                user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                joined_at TIMESTAMP DEFAULT NOW(),
                UNIQUE(sub_group_id, user_id)
            );
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS sub_group_messages (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                sub_group_id UUID REFERENCES sub_groups(id) ON DELETE CASCADE,
                user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                message TEXT NOT NULL,
                timestamp TIMESTAMP DEFAULT NOW()
            );
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS community_events (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                community_id UUID REFERENCES communities(id) ON DELETE CASCADE,
                title VARCHAR(255) NOT NULL,
                description TEXT DEFAULT '',
                location VARCHAR(255) DEFAULT '',
                date TIMESTAMP NOT NULL,
                price FLOAT DEFAULT 0,
                slots INTEGER DEFAULT 0,
                image_url TEXT DEFAULT '',
                created_by UUID REFERENCES users(id) ON DELETE CASCADE,
                event_type TEXT DEFAULT 'event',
                duration_days INTEGER DEFAULT 1,
                difficulty TEXT DEFAULT 'easy',
                includes TEXT[] DEFAULT '{}',
                excludes TEXT[] DEFAULT '{}',
                meeting_point TEXT DEFAULT '',
                end_date TIMESTAMP,
                max_altitude_m FLOAT DEFAULT 0,
                total_distance_km FLOAT DEFAULT 0,
                created_at TIMESTAMP DEFAULT NOW()
            );
        """)

        # Trip columns migration for existing tables
        for col_sql in [
            "ALTER TABLE community_events ADD COLUMN IF NOT EXISTS event_type TEXT DEFAULT 'event'",
            "ALTER TABLE community_events ADD COLUMN IF NOT EXISTS duration_days INTEGER DEFAULT 1",
            "ALTER TABLE community_events ADD COLUMN IF NOT EXISTS difficulty TEXT DEFAULT 'easy'",
            "ALTER TABLE community_events ADD COLUMN IF NOT EXISTS includes TEXT[] DEFAULT '{}'",
            "ALTER TABLE community_events ADD COLUMN IF NOT EXISTS excludes TEXT[] DEFAULT '{}'",
            "ALTER TABLE community_events ADD COLUMN IF NOT EXISTS meeting_point TEXT DEFAULT ''",
            "ALTER TABLE community_events ADD COLUMN IF NOT EXISTS end_date TIMESTAMP",
            "ALTER TABLE community_events ADD COLUMN IF NOT EXISTS max_altitude_m FLOAT DEFAULT 0",
            "ALTER TABLE community_events ADD COLUMN IF NOT EXISTS total_distance_km FLOAT DEFAULT 0",
        ]:
            await conn.execute(f"""
                DO $$ BEGIN {col_sql};
                EXCEPTION WHEN duplicate_column THEN NULL;
                END $$;
            """)

        # Event itinerary table for multi-day trips/treks
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS event_itinerary (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                event_id UUID NOT NULL REFERENCES community_events(id) ON DELETE CASCADE,
                day_number INTEGER NOT NULL,
                title TEXT NOT NULL,
                description TEXT DEFAULT '',
                activities TEXT[] DEFAULT '{}',
                meals_included TEXT[] DEFAULT '{}',
                accommodation TEXT DEFAULT '',
                distance_km FLOAT DEFAULT 0,
                elevation_m FLOAT DEFAULT 0,
                created_at TIMESTAMP DEFAULT NOW()
            );
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS community_event_bookings (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                event_id UUID REFERENCES community_events(id) ON DELETE CASCADE,
                user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                payment_status VARCHAR(50) DEFAULT 'pending',
                payment_id VARCHAR(255) DEFAULT '',
                amount FLOAT DEFAULT 0,
                created_at TIMESTAMP DEFAULT NOW(),
                UNIQUE(event_id, user_id)
            );
        """)

        # Add image_url and message_type columns to messages table
        await conn.execute("""
            DO $$ BEGIN
                ALTER TABLE messages ADD COLUMN IF NOT EXISTS image_url TEXT DEFAULT '';
            EXCEPTION WHEN duplicate_column THEN NULL;
            END $$;
        """)
        await conn.execute("""
            DO $$ BEGIN
                ALTER TABLE messages ADD COLUMN IF NOT EXISTS message_type VARCHAR(20) DEFAULT 'text';
            EXCEPTION WHEN duplicate_column THEN NULL;
            END $$;
        """)

        # Add image_url and message_type columns to community_messages table
        await conn.execute("""
            DO $$ BEGIN
                ALTER TABLE community_messages ADD COLUMN IF NOT EXISTS image_url TEXT DEFAULT '';
            EXCEPTION WHEN duplicate_column THEN NULL;
            END $$;
        """)
        await conn.execute("""
            DO $$ BEGIN
                ALTER TABLE community_messages ADD COLUMN IF NOT EXISTS message_type VARCHAR(20) DEFAULT 'text';
            EXCEPTION WHEN duplicate_column THEN NULL;
            END $$;
        """)

        # Add image_url and message_type columns to sub_group_messages table
        await conn.execute("""
            DO $$ BEGIN
                ALTER TABLE sub_group_messages ADD COLUMN IF NOT EXISTS image_url TEXT DEFAULT '';
            EXCEPTION WHEN duplicate_column THEN NULL;
            END $$;
        """)
        await conn.execute("""
            DO $$ BEGIN
                ALTER TABLE sub_group_messages ADD COLUMN IF NOT EXISTS message_type VARCHAR(20) DEFAULT 'text';
            EXCEPTION WHEN duplicate_column THEN NULL;
            END $$;
        """)

        # Reels
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS reels (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                media_url TEXT NOT NULL,
                media_type VARCHAR(20) DEFAULT 'image',
                caption TEXT DEFAULT '',
                likes_count INTEGER DEFAULT 0,
                comments_count INTEGER DEFAULT 0,
                created_at TIMESTAMP DEFAULT NOW()
            );
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS reel_likes (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                reel_id UUID REFERENCES reels(id) ON DELETE CASCADE,
                user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                created_at TIMESTAMP DEFAULT NOW(),
                UNIQUE(reel_id, user_id)
            );
        """)

        await conn.execute("""
            CREATE TABLE IF NOT EXISTS reel_comments (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                reel_id UUID REFERENCES reels(id) ON DELETE CASCADE,
                user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                text TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT NOW()
            );
        """)


async def seed_demo_data():
    """Insert demo users, posts, and events if the DB is empty."""
    async with pool.acquire() as conn:
        # Check if demo data already exists
        count = await conn.fetchval("SELECT COUNT(*) FROM users WHERE email LIKE '%@demo.com' OR email LIKE '%@strangermeet.com'")
        if count and count > 0:
            return  # Already seeded

        import bcrypt
        pw = bcrypt.hashpw(b"demo1234", bcrypt.gensalt()).decode('utf-8')

        # Insert demo users
        users_data = [
            ("Aarav Sharma", "aarav@demo.com", pw, "+91 98765 43210",
             "Travel lover & photographer. Always looking for the next adventure!",
             ["Travel", "Photography", "Music"],
             "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=200&h=200&fit=crop&crop=face"),
            ("Priya Patel", "priya@demo.com", pw, "+91 87654 32109",
             "Foodie | Fitness enthusiast | Weekend trekker",
             ["Food", "Fitness", "Travel"],
             "https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=200&h=200&fit=crop&crop=face"),
            ("Rohan Mehta", "rohan@demo.com", pw, "+91 76543 21098",
             "Tech geek by day, gamer by night. Let's connect!",
             ["Technology", "Gaming", "Movies"],
             "https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?w=200&h=200&fit=crop&crop=face"),
            ("Ananya Singh", "ananya@demo.com", pw, "+91 65432 10987",
             "Art & music is life. Looking to meet creative souls.",
             ["Art", "Music", "Photography"],
             "https://images.unsplash.com/photo-1524504388940-b1c1722653e1?w=200&h=200&fit=crop&crop=face"),
            ("Vikram Joshi", "vikram@demo.com", pw, "+91 54321 09876",
             "Sports fanatic. Marathon runner. Coffee addict.",
             ["Sports", "Fitness", "Cooking"],
             "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=200&h=200&fit=crop&crop=face"),
        ]

        user_ids = []
        for name, email, password, phone, bio, interests, img in users_data:
            row = await conn.fetchrow(
                """INSERT INTO users (name, email, password_hash, phone, bio, interests, profile_image_url)
                   VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id""",
                name, email, password, phone, bio, interests, img
            )
            user_ids.append(row["id"])

        # Insert demo posts
        posts_data = [
            (user_ids[0], "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=600&h=600&fit=crop",
             "When life gives you limes, arrange them in a zesty tableau and create a 'lime-light' masterpiece! 🍋✨"),
            (user_ids[1], "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=600&h=600&fit=crop",
             "Sunday brunch done right! Nothing beats homemade pasta with fresh basil 🍝"),
            (user_ids[2], "https://images.unsplash.com/photo-1519389950473-47ba0277781c?w=600&h=600&fit=crop",
             "Hackathon weekend! Built an AI chatbot in 48 hours. Sleep is overrated 💻🚀"),
            (user_ids[3], "https://images.unsplash.com/photo-1513364776144-60967b0f800f?w=600&h=600&fit=crop",
             "Art isn't what you see, but what you make others see 🎨"),
            (user_ids[4], "https://images.unsplash.com/photo-1461896836934-bd45ba8fcf9b?w=600&h=600&fit=crop",
             "Morning run by the lake. 10km done before breakfast! 🏃‍♂️"),
            (user_ids[0], "https://images.unsplash.com/photo-1501785888041-af3ef285b470?w=600&h=600&fit=crop",
             "Lost in the mountains and I don't want to be found 🏔️"),
            (user_ids[1], "https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=600&h=600&fit=crop",
             "Found this hidden gem of a cafe! The ambiance is everything ☕"),
            (user_ids[3], "https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=600&h=600&fit=crop",
             "Live music nights are the best therapy 🎵"),
        ]

        post_ids = []
        for uid, img, caption in posts_data:
            row = await conn.fetchrow(
                """INSERT INTO posts (user_id, image_url, caption, likes_count)
                   VALUES ($1, $2, $3, $4) RETURNING id""",
                uid, img, caption, 0
            )
            post_ids.append(row["id"])

        # Add some likes
        import random
        for pid in post_ids:
            likers = random.sample(user_ids, random.randint(1, 4))
            for liker in likers:
                await conn.execute(
                    "INSERT INTO post_likes (post_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
                    pid, liker
                )
            like_count = await conn.fetchval(
                "SELECT COUNT(*) FROM post_likes WHERE post_id = $1", pid
            )
            await conn.execute(
                "UPDATE posts SET likes_count = $1 WHERE id = $2", like_count, pid
            )

        # Add some comments
        comments_data = [
            (post_ids[0], user_ids[1], "This view is insane! Where is this? 😍"),
            (post_ids[0], user_ids[2], "Adding this to my bucket list!"),
            (post_ids[1], user_ids[0], "Recipe please!! 🙏"),
            (post_ids[1], user_ids[4], "That looks delicious!"),
            (post_ids[2], user_ids[3], "That's so cool! What stack did you use?"),
            (post_ids[3], user_ids[0], "Beautiful work! Love the colors"),
            (post_ids[4], user_ids[1], "Impressive! I can barely do 5km 😅"),
            (post_ids[5], user_ids[2], "Take me with you next time!"),
            (post_ids[6], user_ids[3], "Where is this? Need to visit!"),
            (post_ids[7], user_ids[4], "Nothing beats live music 🎶"),
        ]

        for pid, uid, text in comments_data:
            await conn.execute(
                "INSERT INTO comments (post_id, user_id, text) VALUES ($1, $2, $3)",
                pid, uid, text
            )

        # Insert demo events
        from datetime import datetime, timedelta
        events_data = [
            (user_ids[0], "Himalaya Base Camp Trek",
             "3-day trek to the base camp with stunning views. All equipment provided. Beginners welcome!",
             "Manali, Himachal Pradesh", datetime.now() + timedelta(days=15), 4999.0, 20,
             "https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=600&h=400&fit=crop"),
            (user_ids[1], "Street Food Walk - Old Delhi",
             "Explore the best street food spots in Chandni Chowk. Taste 10+ dishes across 2km walk.",
             "Chandni Chowk, Delhi", datetime.now() + timedelta(days=7), 799.0, 15,
             "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=600&h=400&fit=crop"),
            (user_ids[2], "Weekend Hackathon",
             "Build something amazing in 48 hours! Teams of 3-4. Prizes worth 50K. Free food & drinks.",
             "WeWork, Bangalore", datetime.now() + timedelta(days=10), 0.0, 50,
             "https://images.unsplash.com/photo-1504384308090-c894fdcc538d?w=600&h=400&fit=crop"),
            (user_ids[3], "Sunset Painting Workshop",
             "Learn watercolor painting while watching the sunset at Juhu Beach. All materials provided.",
             "Juhu Beach, Mumbai", datetime.now() + timedelta(days=5), 1499.0, 12,
             "https://images.unsplash.com/photo-1460661419201-fd4cecdf8a8b?w=600&h=400&fit=crop"),
            (user_ids[4], "Mumbai Marathon Training",
             "8-week training program for the upcoming Mumbai Marathon. All fitness levels welcome.",
             "Marine Drive, Mumbai", datetime.now() + timedelta(days=3), 2999.0, 30,
             "https://images.unsplash.com/photo-1552674605-db6ffd4facb5?w=600&h=400&fit=crop"),
        ]

        for uid, title, desc, loc, date, price, slots, img in events_data:
            await conn.execute(
                """INSERT INTO events (title, description, location, date, price, slots, image_url, created_by)
                   VALUES ($1, $2, $3, $4, $5, $6, $7, $8)""",
                title, desc, loc, date, price, slots, img, uid
            )

        # Insert demo stories
        stories_data = [
            (user_ids[0],
             "https://images.unsplash.com/photo-1682687220742-aba13b6e50ba?w=400&h=700&fit=crop",
             "Exploring the mountains today!"),
            (user_ids[1],
             "https://images.unsplash.com/photo-1543353071-873f17a7a088?w=400&h=700&fit=crop",
             "Brunch vibes"),
            (user_ids[2],
             "https://images.unsplash.com/photo-1550745165-9bc0b252726f?w=400&h=700&fit=crop",
             "Retro gaming night"),
            (user_ids[3],
             "https://images.unsplash.com/photo-1460661419201-fd4cecdf8a8b?w=400&h=700&fit=crop",
             "New painting session"),
        ]

        for uid, img, caption in stories_data:
            await conn.execute(
                """INSERT INTO stories (user_id, image_url, caption)
                   VALUES ($1, $2, $3)""",
                uid, img, caption
            )

        # Make Aarav a partner (community admin)
        await conn.execute("UPDATE users SET role = 'partner' WHERE id = $1", user_ids[0])

        # ──────────────────────────────────────────────
        # COMMUNITY: Trek With Strangers (Main community)
        # ──────────────────────────────────────────────
        trek_row = await conn.fetchrow(
            """INSERT INTO communities (name, description, image_url, category, is_private, created_by, members_count)
               VALUES ($1, $2, $3, $4, $5, $6, 5) RETURNING id""",
            "Trek With Strangers",
            "Join strangers for unforgettable treks, morning activities, evening jams and weekend adventures across India. Make new friends, explore new places!",
            "https://images.unsplash.com/photo-1551632811-561732d1e306?w=600&h=400&fit=crop",
            "Travel", False, user_ids[0]
        )
        trek_id = str(trek_row["id"])

        # Add ALL 5 users as members
        await conn.execute(
            "INSERT INTO community_members (community_id, user_id, role, status) VALUES ($1, $2, 'admin', 'active')",
            trek_id, user_ids[0]
        )
        for uid in user_ids[1:]:
            await conn.execute(
                "INSERT INTO community_members (community_id, user_id, role, status) VALUES ($1, $2, 'member', 'active') ON CONFLICT DO NOTHING",
                trek_id, uid
            )

        # Sub-groups under Trek With Strangers
        sub_groups_data = [
            (trek_id, "Weekend Trips", "Plan weekend getaways, road trips and multi-day treks with the group", "trip", user_ids[0]),
            (trek_id, "Morning Play", "Early morning sports, yoga, running, cricket, badminton - start your day active!", "meetup", user_ids[0]),
            (trek_id, "Evening Sing", "Evening music jams, campfire singing, open mic nights and karaoke sessions", "meetup", user_ids[0]),
            (trek_id, "Gym Buddies", "Find gym partners near you, share workout routines and fitness tips", "gym", user_ids[4]),
            (trek_id, "Online Meetups", "Virtual hangouts, movie nights, game sessions and online events", "online_meet", user_ids[2]),
        ]

        sub_group_ids = []
        for cid, sg_name, desc, sg_type, uid in sub_groups_data:
            row = await conn.fetchrow(
                "INSERT INTO sub_groups (community_id, name, description, type, created_by) VALUES ($1, $2, $3, $4, $5) RETURNING id",
                cid, sg_name, desc, sg_type, uid
            )
            sub_group_ids.append(row["id"])
            # Add creator + some members to each sub-group
            await conn.execute(
                "INSERT INTO sub_group_members (sub_group_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
                str(row["id"]), uid
            )
            for member_uid in random.sample(user_ids, min(3, len(user_ids))):
                await conn.execute(
                    "INSERT INTO sub_group_members (sub_group_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
                    str(row["id"]), member_uid
                )

        # Sub-group chat messages
        sg_messages = [
            (str(sub_group_ids[0]), user_ids[0], "Hey everyone! Planning a Manali trip on 15th April. Who's in?"),
            (str(sub_group_ids[0]), user_ids[1], "Count me in! Should we take the Hampta Pass route?"),
            (str(sub_group_ids[0]), user_ids[2], "I'm in! First time trekking, any tips?"),
            (str(sub_group_ids[1]), user_ids[4], "Morning cricket at Marine Drive tomorrow 6 AM. Need 4 more players!"),
            (str(sub_group_ids[1]), user_ids[1], "I'll be there! Can bring 2 friends"),
            (str(sub_group_ids[1]), user_ids[0], "Yoga session at Shivaji Park every Saturday 7 AM. Join us!"),
            (str(sub_group_ids[2]), user_ids[3], "Open mic night this Friday at Prithvi Theatre cafe. Who's coming?"),
            (str(sub_group_ids[2]), user_ids[0], "I'll bring my guitar! Any song requests?"),
            (str(sub_group_ids[2]), user_ids[1], "Let's do some Bollywood classics!"),
            (str(sub_group_ids[3]), user_ids[4], "New workout plan: Push Pull Legs. Anyone want to try together?"),
            (str(sub_group_ids[4]), user_ids[2], "Movie night this Saturday! Voting for the movie in comments"),
        ]

        for sgid, uid, msg in sg_messages:
            await conn.execute(
                "INSERT INTO sub_group_messages (sub_group_id, user_id, message) VALUES ($1, $2, $3)",
                sgid, uid, msg
            )

        # Community posts in Trek With Strangers
        comm_posts_data = [
            (trek_id, user_ids[0],
             "https://images.unsplash.com/photo-1551632811-561732d1e306?w=600&h=600&fit=crop",
             "Our Kedarkantha trek last weekend was EPIC! 12 strangers became lifelong friends. Next trip: Hampta Pass in April!"),
            (trek_id, user_ids[1],
             "https://images.unsplash.com/photo-1501785888041-af3ef285b470?w=600&h=600&fit=crop",
             "Sunrise at Triund was worth every step. Budget: Rs 3500 for 2 days including food, stay and transport from Delhi."),
            (trek_id, user_ids[4],
             "https://images.unsplash.com/photo-1552674605-db6ffd4facb5?w=600&h=600&fit=crop",
             "Morning run group is growing! 15 strangers now run together at Marine Drive every morning at 6 AM. Join us!"),
            (trek_id, user_ids[3],
             "https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=600&h=600&fit=crop",
             "Last night's campfire jam was incredible. 20 people singing under the stars at Pawna Lake. Pure magic!"),
            (trek_id, user_ids[2],
             "https://images.unsplash.com/photo-1504384308090-c894fdcc538d?w=600&h=400&fit=crop",
             "Weekend hackathon at WeWork was amazing! Built an app to find trek buddies. Ironic, right?"),
            (trek_id, user_ids[0],
             "https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=600&h=600&fit=crop",
             "Trip budget breakdown for Spiti Valley: Transport Rs 4000, Stay Rs 3000, Food Rs 2000, Permits Rs 500. Total: Rs 9500 for 5 days!"),
        ]

        for cid, uid, img, caption in comm_posts_data:
            await conn.execute(
                "INSERT INTO community_posts (community_id, user_id, image_url, caption) VALUES ($1, $2, $3, $4)",
                cid, uid, img, caption
            )

        # Community events under Trek With Strangers
        # Regular events (non-trip)
        regular_events_data = [
            (trek_id, user_ids[4], "Morning Cricket League",
             "Join our weekly cricket matches every Sunday morning at Marine Drive. All skill levels welcome. Just bring your enthusiasm!",
             "Marine Drive, Mumbai", datetime.now() + timedelta(days=3), 0.0, 30,
             "https://images.unsplash.com/photo-1531415074968-036ba1b575da?w=600&h=400&fit=crop"),
            (trek_id, user_ids[3], "Campfire & Music Night",
             "Evening campfire with live music, stories and snacks at Pawna Lake. Bring your instruments! Food and transport included.",
             "Pawna Lake, Lonavala", datetime.now() + timedelta(days=7), 1499.0, 25,
             "https://images.unsplash.com/photo-1475483768296-6163e08872a1?w=600&h=400&fit=crop"),
            (trek_id, user_ids[1], "Street Food Walk - Old Delhi",
             "Explore 10+ legendary street food spots in Chandni Chowk. Walk, eat, repeat! Budget-friendly food tour.",
             "Chandni Chowk, Delhi", datetime.now() + timedelta(days=10), 799.0, 15,
             "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=600&h=400&fit=crop"),
        ]

        for cid, uid, title, desc, loc, date, price, slots, img in regular_events_data:
            await conn.execute(
                """INSERT INTO community_events (community_id, title, description, location, date, price, slots, image_url, created_by)
                   VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)""",
                cid, title, desc, loc, date, price, slots, img, uid
            )

        # ── TRIP 1: Hampta Pass Trek - 5 Days ──
        hampta_start = datetime.now() + timedelta(days=20)
        hampta_end = hampta_start + timedelta(days=4)
        hampta_row = await conn.fetchrow(
            """INSERT INTO community_events (
                community_id, title, description, location, date, price, slots, image_url, created_by,
                event_type, duration_days, difficulty, includes, excludes, meeting_point, end_date, max_altitude_m, total_distance_km
            ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18) RETURNING id""",
            trek_id,
            "Hampta Pass Trek - 5 Days",
            "Experience the breathtaking Hampta Pass trek, one of India's most scenic crossover treks. "
            "Trek through lush green valleys on one side and barren landscapes of Lahaul on the other. "
            "This 5-day adventure takes you through dense pine forests, vast meadows carpeted with wildflowers, "
            "glacial streams, and the iconic Hampta Pass at 4,270m. The trek culminates with a visit to the "
            "stunning Chandratal Lake, a pristine high-altitude lake surrounded by the Spiti landscape.\n\n"
            "Perfect for those seeking a moderate challenge with extraordinary reward. Our experienced guides "
            "ensure safety at every step while our support team handles all logistics so you can focus on "
            "soaking in the Himalayan beauty.",
            "Manali, Himachal Pradesh",
            hampta_start, 8999.0, 20,
            "https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=600&h=400&fit=crop",
            user_ids[0],
            "trip", 5, "moderate",
            ["Camping tents", "All meals", "Trek guide", "First aid", "Permits", "Transport from Manali"],
            ["Personal expenses", "Travel insurance", "Gear rental", "Tips"],
            "Mall Road, Manali - 8:00 AM",
            hampta_end, 4270.0, 35.0
        )
        hampta_event_id = str(hampta_row["id"])

        # Hampta Pass itinerary
        hampta_itinerary = [
            (hampta_event_id, 1, "Manali to Jobra",
             "Begin your trek from Manali with a short drive to Jobra. Trek through beautiful pine and maple forests along the Rani Nallah. "
             "The trail is gentle and perfect for warming up. Set up camp at Jobra with stunning views of the surrounding peaks.",
             ["Drive from Manali to Jobra trailhead", "Trek through pine forests", "Cross wooden bridges", "Camp setup and evening tea"],
             ["Lunch", "Dinner"], "Tent camping", 8.0, 3150.0),
            (hampta_event_id, 2, "Jobra to Balu Ka Ghera",
             "A spectacular day through alpine meadows and river crossings. The landscape transforms from dense forest to open meadows. "
             "Cross multiple glacial streams (be prepared to get your feet wet!). Reach Balu Ka Ghera, a vast sandy plain surrounded by towering peaks.",
             ["Trek through alpine meadows", "Cross glacial streams", "Spot Himalayan wildflowers", "Photography at scenic viewpoints"],
             ["Breakfast", "Lunch", "Dinner"], "Tent camping", 10.0, 3600.0),
            (hampta_event_id, 3, "Balu Ka Ghera to Siagoru via Hampta Pass",
             "Summit day! The climb to Hampta Pass (4,270m) is steep but rewarding. At the top, witness the dramatic contrast - "
             "lush green Kullu Valley on one side and the barren moonscape of Lahaul on the other. Descend to Siagoru for the night.",
             ["Early morning start for pass crossing", "Summit Hampta Pass at 4,270m", "Panoramic views of Lahaul and Kullu valleys", "Descent to Siagoru campsite"],
             ["Breakfast", "Packed lunch", "Dinner"], "Tent camping", 8.0, 4270.0),
            (hampta_event_id, 4, "Siagoru to Chatru",
             "An easy descent day following the Chandra river. The landscape is dramatically different from where you started - "
             "barren mountains, wide river valleys and the raw beauty of Lahaul. Reach Chatru and enjoy a relaxed afternoon by the river.",
             ["Easy descent along Chandra river", "Explore Lahaul landscape", "Riverside rest and photography", "Campfire and stargazing"],
             ["Breakfast", "Lunch", "Dinner"], "Tent camping", 6.0, 3360.0),
            (hampta_event_id, 5, "Chatru to Chandratal Lake & Return to Manali",
             "Drive to Chandratal Lake, one of the most beautiful high-altitude lakes in India. The crescent-shaped lake with its "
             "crystal-clear blue-green waters is a sight you will never forget. After spending time at the lake, drive back to Manali.",
             ["Drive to Chandratal Lake", "Explore the crescent-shaped lake", "Photography at the lake", "Drive back to Manali"],
             ["Breakfast", "Lunch"], "N/A - return to Manali", 3.0, 4300.0),
        ]

        for eid, day_num, title, desc, activities, meals, accommodation, dist, elev in hampta_itinerary:
            await conn.execute(
                """INSERT INTO event_itinerary (event_id, day_number, title, description, activities, meals_included, accommodation, distance_km, elevation_m)
                   VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)""",
                eid, day_num, title, desc, activities, meals, accommodation, dist, elev
            )

        # Add some bookings to Hampta Pass trek
        for uid in user_ids[:3]:
            await conn.execute(
                "INSERT INTO community_event_bookings (event_id, user_id, payment_status, amount) VALUES ($1, $2, 'completed', $3) ON CONFLICT DO NOTHING",
                hampta_event_id, uid, 8999.0
            )

        # ── TRIP 2: Weekend Lonavala Trek - 2 Days ──
        lonavala_start = datetime.now() + timedelta(days=12)
        lonavala_end = lonavala_start + timedelta(days=1)
        lonavala_row = await conn.fetchrow(
            """INSERT INTO community_events (
                community_id, title, description, location, date, price, slots, image_url, created_by,
                event_type, duration_days, difficulty, includes, excludes, meeting_point, end_date, max_altitude_m, total_distance_km
            ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18) RETURNING id""",
            trek_id,
            "Weekend Lonavala Trek - 2 Days",
            "Escape the city for a weekend of adventure near Mumbai! Trek to the historic Rajmachi Fort, "
            "explore the ancient Kondane Caves, and camp under the stars. This beginner-friendly trek is "
            "perfect for first-timers and weekend warriors looking for a quick nature getaway.",
            "Lonavala, Maharashtra",
            lonavala_start, 2499.0, 30,
            "https://images.unsplash.com/photo-1501785888041-af3ef285b470?w=600&h=400&fit=crop",
            user_ids[0],
            "trip", 2, "easy",
            ["Camping", "Meals", "Guide", "First aid"],
            ["Travel to Lonavala", "Personal expenses"],
            "Lonavala Railway Station - 7:00 AM",
            lonavala_end, 920.0, 18.0
        )
        lonavala_event_id = str(lonavala_row["id"])

        # Lonavala itinerary
        lonavala_itinerary = [
            (lonavala_event_id, 1, "Lonavala to Rajmachi Fort",
             "Meet at Lonavala Railway Station and begin the trek to Rajmachi Fort. The trail passes through lush green "
             "countryside, small villages and waterfalls (in monsoon). Explore the twin forts of Shrivardhan and Manaranjan. "
             "Set up camp near the fort and enjoy a campfire night with music and stories.",
             ["Trek from Lonavala to Rajmachi", "Explore Shrivardhan Fort", "Explore Manaranjan Fort", "Campfire with music and stories"],
             ["Lunch", "Evening snacks", "Dinner"], "Tent camping", 15.0, 920.0),
            (lonavala_event_id, 2, "Sunrise, Kondane Caves & Return",
             "Wake up early for a spectacular sunrise over the Sahyadri hills. After breakfast, trek to the ancient Kondane "
             "Buddhist Caves dating back to the 1st century BCE. Explore the intricate rock-cut architecture before trekking "
             "back to Lonavala by afternoon.",
             ["Sunrise viewing from fort", "Trek to Kondane Caves", "Explore Buddhist cave architecture", "Trek back to Lonavala"],
             ["Breakfast", "Lunch"], "N/A - return home", 3.0, 600.0),
        ]

        for eid, day_num, title, desc, activities, meals, accommodation, dist, elev in lonavala_itinerary:
            await conn.execute(
                """INSERT INTO event_itinerary (event_id, day_number, title, description, activities, meals_included, accommodation, distance_km, elevation_m)
                   VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)""",
                eid, day_num, title, desc, activities, meals, accommodation, dist, elev
            )

        # Community group chat messages
        comm_chat_msgs = [
            (trek_id, user_ids[0], "Welcome to Trek With Strangers! Introduce yourself and share what adventures you're looking for!"),
            (trek_id, user_ids[1], "Hi everyone! I'm Priya from Mumbai. Love trekking and trying new food spots. Looking for weekend trek buddies!"),
            (trek_id, user_ids[2], "Hey! Rohan here, tech nerd but want to get outdoors more. Any beginner-friendly treks coming up?"),
            (trek_id, user_ids[3], "Ananya from Delhi. I play guitar and love campfire sessions. The Evening Sing group is going to be lit!"),
            (trek_id, user_ids[4], "Vikram here, marathon runner. Started the Morning Play group for morning sports. Join if you're an early bird!"),
            (trek_id, user_ids[0], "Awesome group! Hampta Pass trek dates are out - 15th to 18th April. Rs 6999 all inclusive. Sign up in Events!"),
        ]

        for cid, uid, msg in comm_chat_msgs:
            await conn.execute(
                "INSERT INTO community_messages (community_id, user_id, message) VALUES ($1, $2, $3)",
                cid, uid, msg
            )

        # ──────────────────────────────────────────────
        # MORE COMMUNITIES
        # ──────────────────────────────────────────────
        more_communities = [
            (user_ids[1], "Foodies of Mumbai", "Discover hidden food gems in Mumbai. Street food walks, restaurant reviews, cooking meetups!",
             "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=600&h=400&fit=crop",
             "Food", False),
            (user_ids[2], "Tech Innovators Hub", "Hackathons, coding sessions, tech talks. Build cool stuff together!",
             "https://images.unsplash.com/photo-1519389950473-47ba0277781c?w=600&h=400&fit=crop",
             "Technology", False),
            (user_ids[3], "Art & Music Collective", "For creative souls - painting workshops, music jams, poetry nights",
             "https://images.unsplash.com/photo-1513364776144-60967b0f800f?w=600&h=400&fit=crop",
             "Art", False),
            (user_ids[4], "Fitness Warriors", "Gym partners, running groups, yoga sessions. Get fit together!",
             "https://images.unsplash.com/photo-1552674605-db6ffd4facb5?w=600&h=400&fit=crop",
             "Fitness", True),
        ]

        for uid, c_name, desc, img, cat, is_private in more_communities:
            row = await conn.fetchrow(
                """INSERT INTO communities (name, description, image_url, category, is_private, created_by, members_count)
                   VALUES ($1, $2, $3, $4, $5, $6, 1) RETURNING id""",
                c_name, desc, img, cat, is_private, uid
            )
            await conn.execute(
                "INSERT INTO community_members (community_id, user_id, role, status) VALUES ($1, $2, 'admin', 'active')",
                str(row["id"]), uid
            )
            # Add 2-3 random members
            for member_uid in random.sample(user_ids, 3):
                if member_uid != uid:
                    await conn.execute(
                        "INSERT INTO community_members (community_id, user_id, role, status) VALUES ($1, $2, 'member', 'active') ON CONFLICT DO NOTHING",
                        str(row["id"]), member_uid
                    )
                    await conn.execute(
                        "UPDATE communities SET members_count = members_count + 1 WHERE id = $1",
                        str(row["id"])
                    )

        # ──────────────────────────────────────────────
        # FRIENDSHIPS (all demo users are friends)
        # ──────────────────────────────────────────────
        friendships_data = [
            (user_ids[0], user_ids[1], "accepted"),
            (user_ids[0], user_ids[2], "accepted"),
            (user_ids[0], user_ids[3], "accepted"),
            (user_ids[0], user_ids[4], "accepted"),
            (user_ids[1], user_ids[2], "accepted"),
            (user_ids[1], user_ids[3], "accepted"),
            (user_ids[2], user_ids[4], "accepted"),
            (user_ids[3], user_ids[4], "pending"),
        ]

        for req_id, addr_id, f_status in friendships_data:
            await conn.execute(
                "INSERT INTO friendships (requester_id, addressee_id, status) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING",
                req_id, addr_id, f_status
            )

        # ──────────────────────────────────────────────
        # REELS
        # ──────────────────────────────────────────────
        reels_data = [
            (user_ids[0], "https://images.unsplash.com/photo-1551632811-561732d1e306?w=400&h=700&fit=crop",
             "image", "Kedarkantha summit at sunrise! Worth every step of the trek"),
            (user_ids[1], "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=400&h=700&fit=crop",
             "image", "Street food paradise in Chandni Chowk! This chole bhature is to die for"),
            (user_ids[2], "https://images.unsplash.com/photo-1550745165-9bc0b252726f?w=400&h=700&fit=crop",
             "image", "Built a trek buddy finder app this weekend! Who wants to test it?"),
            (user_ids[3], "https://images.unsplash.com/photo-1475483768296-6163e08872a1?w=400&h=700&fit=crop",
             "image", "Campfire jam at Pawna Lake. Guitar + stars + strangers = best night ever"),
            (user_ids[4], "https://images.unsplash.com/photo-1461896836934-bd45ba8fcf9b?w=400&h=700&fit=crop",
             "image", "Morning run crew at Marine Drive. 15 strangers, one mission: 10km before sunrise"),
        ]

        for uid, url, media_type, caption in reels_data:
            await conn.execute(
                "INSERT INTO reels (user_id, media_url, media_type, caption) VALUES ($1, $2, $3, $4)",
                uid, url, media_type, caption
            )

        # ──────────────────────────────────────────────
        # SPECIAL LOGIN USER (for you to test with)
        # ──────────────────────────────────────────────
        test_pw = bcrypt.hashpw(b"naveen123", bcrypt.gensalt()).decode('utf-8')
        test_row = await conn.fetchrow(
            """INSERT INTO users (name, email, password_hash, phone, bio, interests, profile_image_url, role)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id""",
            "Naveen", "naveen@strangermeet.com", test_pw, "+91 99999 88888",
            "Explorer, coder, adventure seeker. Building StrangerMeet!",
            ["Travel", "Technology", "Music", "Fitness"],
            "https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=200&h=200&fit=crop&crop=face",
            "customer"
        )
        test_uid = test_row["id"]

        # Add Naveen to Trek With Strangers community
        await conn.execute(
            "INSERT INTO community_members (community_id, user_id, role, status) VALUES ($1, $2, 'member', 'active') ON CONFLICT DO NOTHING",
            trek_id, test_uid
        )
        await conn.execute("UPDATE communities SET members_count = members_count + 1 WHERE id = $1", trek_id)

        # Make Naveen friends with some demo users
        for friend_uid in user_ids[:3]:
            await conn.execute(
                "INSERT INTO friendships (requester_id, addressee_id, status) VALUES ($1, $2, 'accepted') ON CONFLICT DO NOTHING",
                test_uid, friend_uid
            )

        # Also create a partner test account
        partner_pw = bcrypt.hashpw(b"partner123", bcrypt.gensalt()).decode('utf-8')
        await conn.fetchrow(
            """INSERT INTO users (name, email, password_hash, phone, bio, interests, profile_image_url, role)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id""",
            "StrangerMeet Admin", "admin@strangermeet.com", partner_pw, "+91 99999 77777",
            "Official StrangerMeet community partner. Creating amazing experiences!",
            ["Travel", "Events", "Community"],
            "https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=200&h=200&fit=crop&crop=face",
            "partner"
        )

        print("✅ Demo data seeded: 7 users, 8 posts, 5 communities, Trek With Strangers (5 groups), 8 friendships, 5 reels")
        print("📱 LOGIN CREDENTIALS:")
        print("   Customer: naveen@strangermeet.com / naveen123")
        print("   Partner:  admin@strangermeet.com / partner123")
        print("   Demo:     aarav@demo.com / demo1234 (partner)")
        print("   Demo:     priya@demo.com / demo1234 (customer)")
