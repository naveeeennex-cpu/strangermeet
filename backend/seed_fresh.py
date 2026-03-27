import asyncio
import asyncpg
import bcrypt
from datetime import datetime, timedelta

DB_URL = "postgresql://postgres.lrgjntwdntwqjnewarmk:Naveeeen2026@aws-1-ap-northeast-2.pooler.supabase.com:6543/postgres"


async def seed():
    pool = await asyncpg.create_pool(DB_URL, statement_cache_size=0)

    # ── 1. Partner User ──
    partner_pw = bcrypt.hashpw(b"trek@123", bcrypt.gensalt()).decode()
    partner = await pool.fetchrow(
        """INSERT INTO users (name, email, password_hash, username, phone, bio, role, interests, profile_image_url, cover_image_url)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING id""",
        "Trek With Strangers", "trek@strangermeet.com", partner_pw,
        "trekwithstrangers", "+91 9876543210",
        "Chennai based community for treks, trips, events & meetups. Join us to explore!",
        "partner", ["Travel", "Adventure", "Food", "Music", "Sports"],
        "https://images.unsplash.com/photo-1551632811-561732d1e306?w=200&h=200&fit=crop",
        "https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=800&h=400&fit=crop",
    )
    pid = str(partner["id"])
    print(f"Partner ID: {pid}")

    # ── 2. Demo Users ──
    demo_data = [
        ("Naveen D", "naveen@strangermeet.com", "naveen123", "naveen_d", "+91 8765432100", "CEO of Aptirix | Explorer",
         "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=200&h=200&fit=crop&crop=face",
         ["Travel", "Tech", "Sports"]),
        ("Priya Sharma", "priya@strangermeet.com", "priya123", "priya.sharma", "+91 9988776655", "Travel lover | Foodie | Chennai",
         "https://images.unsplash.com/photo-1524504388940-b1c1722653e1?w=200&h=200&fit=crop&crop=face",
         ["Travel", "Food", "Music"]),
        ("Rahul Kumar", "rahul@strangermeet.com", "rahul123", "rahul_k", "+91 8877665544", "Sports enthusiast | Night owl",
         "https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?w=200&h=200&fit=crop&crop=face",
         ["Sports", "Travel", "Adventure"]),
        ("Anitha R", "anitha@strangermeet.com", "anitha123", "anitha.r", "+91 7766554433", "Singer | Beach person | Adventure seeker",
         "https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=200&h=200&fit=crop&crop=face",
         ["Music", "Travel", "Food"]),
        ("Karthik S", "karthik@strangermeet.com", "karthik123", "karthik_s", "+91 6655443322", "Photographer | Trekker | Foodie",
         "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=200&h=200&fit=crop&crop=face",
         ["Travel", "Food", "Sports"]),
    ]
    demo_ids = []
    for name, email, pw, uname, phone, bio, img, interests in demo_data:
        hashed = bcrypt.hashpw(pw.encode(), bcrypt.gensalt()).decode()
        row = await pool.fetchrow(
            """INSERT INTO users (name, email, password_hash, username, phone, bio, role, interests, profile_image_url)
               VALUES ($1,$2,$3,$4,$5,$6,'customer',$7,$8) RETURNING id""",
            name, email, hashed, uname, phone, bio, interests, img,
        )
        demo_ids.append(str(row["id"]))
        print(f"User: {name} ({uname}) ID: {row['id']}")

    # ── 3. Community ──
    comm = await pool.fetchrow(
        """INSERT INTO communities (name, description, image_url, category, is_private, created_by, members_count)
           VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING id""",
        "Trek With Strangers",
        "Chennai based community for treks, beach trips, food walks, singing events, sports meetups & night outs. Join strangers, make friends!",
        "https://images.unsplash.com/photo-1551632811-561732d1e306?w=600&h=400&fit=crop",
        "Travel", False, pid, 6,
    )
    cid = str(comm["id"])
    print(f"Community ID: {cid}")

    # Add members
    await pool.execute("INSERT INTO community_members (community_id, user_id, role, status) VALUES ($1,$2,'admin','active')", cid, pid)
    for uid in demo_ids:
        await pool.execute("INSERT INTO community_members (community_id, user_id, role, status) VALUES ($1,$2,'member','active')", cid, uid)

    # ── 4. Sub Groups ──
    groups = [
        ("Food Walks", "Explore hidden street food gems across Chennai", "food",
         "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=200&h=200&fit=crop"),
        ("Beach Activities", "Marina, Besant Nagar, ECR beach meetups & water sports", "outdoor",
         "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=200&h=200&fit=crop"),
        ("Kathipara Singing", "Open mic, karaoke nights & jam sessions near Kathipara", "music",
         "https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=200&h=200&fit=crop"),
        ("Night Out", "Late night drives, rooftop hangouts & midnight food runs", "social",
         "https://images.unsplash.com/photo-1519681393784-d120267933ba?w=200&h=200&fit=crop"),
        ("Sports", "Cricket, football, badminton & fitness meetups", "sports",
         "https://images.unsplash.com/photo-1461896836934-bd45ba7296fa?w=200&h=200&fit=crop"),
        ("Events", "Community events, workshops, meetups & hackathons", "event",
         "https://images.unsplash.com/photo-1540575467063-178a50c2df87?w=200&h=200&fit=crop"),
    ]
    for gname, gdesc, gtype, gimg in groups:
        g = await pool.fetchrow(
            """INSERT INTO sub_groups (community_id, name, description, type, created_by, image_url)
               VALUES ($1,$2,$3,$4,$5,$6) RETURNING id""",
            cid, gname, gdesc, gtype, pid, gimg,
        )
        gid = str(g["id"])
        await pool.execute("INSERT INTO sub_group_members (sub_group_id, user_id) VALUES ($1,$2)", gid, pid)
        for uid in demo_ids[:3]:
            await pool.execute("INSERT INTO sub_group_members (sub_group_id, user_id) VALUES ($1,$2)", gid, uid)
        print(f"Group: {gname}")

    # ── 5. Events ──
    now = datetime.utcnow()
    events = [
        ("Marina Beach Sunrise Trek", "Early morning walk along Marina Beach with breakfast at a local spot.", "Marina Beach, Chennai",
         now + timedelta(days=3), 0, 30, "event", 1, "easy",
         "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=600&h=400&fit=crop", "Marina Lighthouse - 5:30 AM"),
        ("Street Food Walk - Sowcarpet", "Explore famous Sowcarpet street food. From jigarthanda to sundal!",
         "Sowcarpet, Chennai", now + timedelta(days=5), 299, 20, "event", 1, "easy",
         "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=600&h=400&fit=crop", "Sowcarpet Market Entrance - 6:00 PM"),
        ("Kathipara Open Mic Night", "Sing your heart out at our open mic night. All genres welcome!",
         "Kathipara, Chennai", now + timedelta(days=7), 0, 50, "event", 1, "easy",
         "https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=600&h=400&fit=crop", "Phoenix Mall Food Court - 7:00 PM"),
        ("Weekend Cricket Match", "Friendly cricket match. All skill levels welcome!",
         "YMCA Ground, Nungambakkam, Chennai", now + timedelta(days=4), 0, 22, "event", 1, "easy",
         "https://images.unsplash.com/photo-1531415074968-036ba1b575da?w=600&h=400&fit=crop", "YMCA Main Gate - 6:00 AM"),
        ("ECR Night Drive & Bonfire", "Late night drive along ECR with bonfire. Music, food & good vibes!",
         "ECR, Chennai", now + timedelta(days=10), 499, 25, "event", 1, "easy",
         "https://images.unsplash.com/photo-1519681393784-d120267933ba?w=600&h=400&fit=crop", "Tidel Park Signal - 10:00 PM"),
    ]
    for title, desc, loc, date, price, slots, etype, dur, diff, img, mp in events:
        e = await pool.fetchrow(
            """INSERT INTO community_events (community_id, title, description, location, date, price, slots, event_type, duration_days, difficulty, image_url, meeting_point, created_by)
               VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) RETURNING id""",
            cid, title, desc, loc, date, price, slots, etype, dur, diff, img, mp, pid,
        )
        print(f"Event: {title}")

    # ── 6. Trips with Itinerary ──
    trips = [
        {
            "title": "Yelagiri Hill Weekend Trek",
            "desc": "Refreshing 2-day trek to Yelagiri hills. Waterfalls, viewpoints, camping under stars!",
            "loc": "Yelagiri Hills, Tamil Nadu",
            "date": now + timedelta(days=14),
            "end_date": now + timedelta(days=15),
            "price": 2499, "slots": 20, "dur": 2, "diff": "easy",
            "img": "https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=600&h=400&fit=crop",
            "mp": "Koyambedu Bus Stand - 6:00 AM", "alt": 1100, "dist": 8,
            "includes": ["Transport from Chennai", "Camping gear", "Meals (2B, 1L, 1D)", "Guide"],
            "excludes": ["Personal expenses", "Travel insurance"],
            "days": [
                (1, "Chennai to Yelagiri", "Drive from Chennai. Trek to Swamimalai viewpoint. Campfire.", "https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=400&h=300&fit=crop",
                 ["Morning: Depart Koyambedu at 6 AM. Scenic drive through Vaniyambadi.", "Afternoon: Arrive base camp. Light lunch. Trek to Swamimalai Hills (4km).", "Evening: Reach viewpoint. Set up camp. Bonfire with music and dinner."]),
                (2, "Waterfall & Return", "Visit Jalagamparai waterfall. Nature walk. Return.", "https://images.unsplash.com/photo-1432405972618-c6b0cfba8b26?w=400&h=300&fit=crop",
                 ["Morning: Sunrise view. Breakfast. Trek to Jalagamparai waterfall.", "Afternoon: Swim at waterfall. Pack up. Lunch at local restaurant.", "Evening: Drive back to Chennai. Drop at Koyambedu by 8 PM."]),
            ]
        },
        {
            "title": "Kodaikanal 3-Day Explorer",
            "desc": "Explore the Princess of Hill Stations! Forests, waterfalls, lake & misty mountains.",
            "loc": "Kodaikanal, Tamil Nadu",
            "date": now + timedelta(days=21),
            "end_date": now + timedelta(days=23),
            "price": 4999, "slots": 15, "dur": 3, "diff": "moderate",
            "img": "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=600&h=400&fit=crop",
            "mp": "Chennai Central - 9:00 PM (Day 0)", "alt": 2133, "dist": 15,
            "includes": ["Train tickets", "Homestay", "All meals", "Local transport", "Guide", "Boating"],
            "excludes": ["Personal expenses", "Snacks", "Travel insurance"],
            "days": [
                (1, "Arrival & Lake", "Arrive Kodaikanal. Kodai Lake, Coakers Walk, Bryant Park.", "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=400&h=300&fit=crop",
                 ["Morning: Arrive at Kodaikanal Road station. Drive up ghat road.", "Afternoon: Check in. Lunch. Kodai Lake boating. Coakers Walk.", "Evening: Bryant Park. Group dinner. Stargazing walk."]),
                (2, "Trekking Day", "Dolphin Nose trek. Vattakanal waterfalls. Pine forest.", "https://images.unsplash.com/photo-1551632811-561732d1e306?w=400&h=300&fit=crop",
                 ["Morning: Breakfast. Trek to Dolphins Nose viewpoint (3km).", "Afternoon: Vattakanal waterfalls. Swimming. Packed lunch in forest.", "Evening: Pine Forest walk. Guna Caves viewpoint. Campfire."]),
                (3, "Berijam Lake & Return", "Berijam Lake. Shopping. Return journey.", "https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?w=400&h=300&fit=crop",
                 ["Morning: Drive to Berijam Lake (forest permit area).", "Afternoon: Return to town. Shopping. Lunch. Pack up.", "Evening: Drive down. Board return train."]),
            ]
        },
        {
            "title": "Pondicherry Beach & Heritage Walk",
            "desc": "Weekend trip to Pondy! French Quarter, Paradise Beach, Auroville & seafood.",
            "loc": "Pondicherry",
            "date": now + timedelta(days=9),
            "end_date": now + timedelta(days=10),
            "price": 1999, "slots": 25, "dur": 2, "diff": "easy",
            "img": "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=600&h=400&fit=crop",
            "mp": "Guindy Bus Stop - 5:30 AM", "alt": 0, "dist": 5,
            "includes": ["AC bus", "Homestay (1 night)", "Breakfast & dinner", "Heritage walk guide", "Boat to Paradise Beach"],
            "excludes": ["Lunch", "Personal shopping"],
            "days": [
                (1, "Chennai to Pondy", "Drive to Pondy. French Quarter heritage walk. Beaches.", "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=400&h=300&fit=crop",
                 ["Morning: Depart Chennai 5:30 AM. Breakfast at Mahabalipuram.", "Afternoon: French Quarter heritage walk. Basilica visit. French cafe lunch.", "Evening: Rock Beach sunset. Promenade walk. Seafood dinner."]),
                (2, "Paradise Beach & Auroville", "Boat to Paradise Beach. Auroville. Return.", "https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?w=400&h=300&fit=crop",
                 ["Morning: Beach yoga. Breakfast. Boat to Paradise Beach. Swimming.", "Afternoon: Auroville & Matrimandir. Lunch at Auroville bakery.", "Evening: Depart for Chennai. Drop at Guindy by 8 PM."]),
            ]
        },
    ]
    for t in trips:
        e = await pool.fetchrow(
            """INSERT INTO community_events (community_id, title, description, location, date, end_date, price, slots, event_type, duration_days, difficulty, image_url, meeting_point, max_altitude_m, total_distance_km, includes, excludes, created_by)
               VALUES ($1,$2,$3,$4,$5,$6,$7,$8,'trip',$9,$10,$11,$12,$13,$14,$15,$16,$17) RETURNING id""",
            cid, t["title"], t["desc"], t["loc"], t["date"], t["end_date"],
            t["price"], t["slots"], t["dur"], t["diff"], t["img"], t["mp"],
            t["alt"], t["dist"], t["includes"], t["excludes"], pid,
        )
        eid = str(e["id"])
        for day_num, day_title, day_desc, day_img, activities in t["days"]:
            await pool.execute(
                """INSERT INTO event_itinerary (event_id, day_number, title, description, image_url, activities)
                   VALUES ($1,$2,$3,$4,$5,$6)""",
                eid, day_num, day_title, day_desc, day_img, activities,
            )
        print(f"Trip: {t['title']} ({t['dur']}D)")

    # ── 7. Friendships ──
    await pool.execute("INSERT INTO friendships (sender_id, receiver_id, status) VALUES ($1,$2,'accepted')", demo_ids[0], demo_ids[1])
    await pool.execute("INSERT INTO friendships (sender_id, receiver_id, status) VALUES ($1,$2,'accepted')", demo_ids[0], demo_ids[2])

    # ── 8. Posts ──
    posts = [
        (demo_ids[1], "What an amazing sunrise at Marina Beach today!", "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=600&h=400&fit=crop"),
        (demo_ids[2], "Weekend cricket with the boys! Anyone up for next Saturday?", "https://images.unsplash.com/photo-1531415074968-036ba1b575da?w=600&h=400&fit=crop"),
        (demo_ids[3], "Open mic night was incredible! Can't wait for the next one.", "https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=600&h=400&fit=crop"),
        (demo_ids[4], "Captured this beauty during the Yelagiri trek. Nature is healing!", "https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=600&h=400&fit=crop"),
    ]
    for uid, caption, img in posts:
        await pool.execute("INSERT INTO posts (user_id, caption, image_url) VALUES ($1,$2,$3)", uid, caption, img)

    await pool.close()

    print("\n" + "=" * 50)
    print("CREDENTIALS")
    print("=" * 50)
    print("\nPARTNER (Trek With Strangers admin):")
    print("  Email:    trek@strangermeet.com")
    print("  Password: trek@123")
    print("  Username: @trekwithstrangers")
    print("\nCUSTOMER accounts:")
    print("  naveen@strangermeet.com  / naveen123  / @naveen_d")
    print("  priya@strangermeet.com   / priya123   / @priya.sharma")
    print("  rahul@strangermeet.com   / rahul123   / @rahul_k")
    print("  anitha@strangermeet.com  / anitha123  / @anitha.r")
    print("  karthik@strangermeet.com / karthik123 / @karthik_s")
    print("\nCOMMUNITY: Trek With Strangers")
    print("  Groups: Food Walks, Beach Activities, Kathipara Singing, Night Out, Sports, Events")
    print("  Events: 5 events + 3 trips with day-wise itinerary")
    print("=" * 50)


asyncio.run(seed())
