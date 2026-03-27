import asyncio
import asyncpg
from datetime import datetime, timedelta

DB = "postgresql://postgres.lrgjntwdntwqjnewarmk:Naveeeen2026@aws-1-ap-northeast-2.pooler.supabase.com:6543/postgres"

async def fix():
    pool = await asyncpg.create_pool(DB, statement_cache_size=0)
    now = datetime.utcnow()
    pid = await pool.fetchval("SELECT id::text FROM users WHERE username = 'trekwithstrangers'")
    cid = await pool.fetchval("SELECT id::text FROM communities WHERE name = 'Trek With Strangers'")

    # Yelagiri itinerary
    yid = await pool.fetchval("SELECT id::text FROM community_events WHERE title LIKE 'Yelagiri%'")
    if yid:
        cnt = await pool.fetchval("SELECT COUNT(*) FROM event_itinerary WHERE event_id = $1", yid)
        if cnt == 0:
            await pool.execute(
                "INSERT INTO event_itinerary (event_id, day_number, title, description, image_url, activities) VALUES ($1,1,$2,$3,$4,$5)",
                yid, "Chennai to Yelagiri", "Drive from Chennai. Trek to Swamimalai viewpoint. Campfire.",
                "https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=400&h=300&fit=crop",
                ["Morning: Depart Koyambedu at 6 AM. Scenic drive.", "Afternoon: Arrive base camp. Trek to Swamimalai (4km).", "Evening: Viewpoint. Camp setup. Bonfire dinner."]
            )
            await pool.execute(
                "INSERT INTO event_itinerary (event_id, day_number, title, description, image_url, activities) VALUES ($1,2,$2,$3,$4,$5)",
                yid, "Waterfall & Return", "Jalagamparai waterfall. Nature walk. Return.",
                "https://images.unsplash.com/photo-1432405972618-c6b0cfba8b26?w=400&h=300&fit=crop",
                ["Morning: Sunrise. Breakfast. Trek to waterfall.", "Afternoon: Swim. Pack up. Lunch.", "Evening: Drive back. Koyambedu by 8 PM."]
            )
            print("Added Yelagiri itinerary")

    # Kodaikanal trip
    e = await pool.fetchrow(
        "INSERT INTO community_events (community_id,title,description,location,date,end_date,price,slots,event_type,duration_days,difficulty,image_url,meeting_point,max_altitude_m,total_distance_km,includes,excludes,created_by) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,'trip',$9,$10,$11,$12,$13,$14,$15,$16,$17) RETURNING id::text",
        cid, "Kodaikanal 3-Day Explorer", "Explore the Princess of Hill Stations! Forests, waterfalls, lake & misty mountains.",
        "Kodaikanal, Tamil Nadu", now+timedelta(days=21), now+timedelta(days=23), 4999, 15, 3, "moderate",
        "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=600&h=400&fit=crop",
        "Chennai Central - 9:00 PM (Day 0)", 2133, 15,
        ["Train tickets", "Homestay", "All meals", "Local transport", "Guide", "Boating"],
        ["Personal expenses", "Snacks", "Travel insurance"], pid
    )
    kid = e["id"]
    for d in [
        (1, "Arrival & Lake", "Arrive Kodaikanal. Kodai Lake, Coakers Walk, Bryant Park.",
         "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=400",
         ["Morning: Arrive Kodaikanal Road station. Drive up.", "Afternoon: Check in. Kodai Lake boating. Coakers Walk.", "Evening: Bryant Park. Group dinner. Stargazing."]),
        (2, "Trekking Day", "Dolphin Nose trek. Vattakanal waterfalls. Pine forest.",
         "https://images.unsplash.com/photo-1551632811-561732d1e306?w=400",
         ["Morning: Trek to Dolphins Nose viewpoint (3km).", "Afternoon: Vattakanal waterfalls. Swimming. Packed lunch.", "Evening: Pine Forest. Guna Caves viewpoint. Campfire."]),
        (3, "Berijam Lake & Return", "Berijam Lake. Shopping. Return journey.",
         "https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?w=400",
         ["Morning: Drive to Berijam Lake.", "Afternoon: Shopping. Lunch. Pack up.", "Evening: Drive down. Board return train."]),
    ]:
        await pool.execute(
            "INSERT INTO event_itinerary (event_id,day_number,title,description,image_url,activities) VALUES ($1,$2,$3,$4,$5,$6)",
            kid, d[0], d[1], d[2], d[3], d[4]
        )
    print("Added Kodaikanal trip + itinerary")

    # Pondicherry trip
    e = await pool.fetchrow(
        "INSERT INTO community_events (community_id,title,description,location,date,end_date,price,slots,event_type,duration_days,difficulty,image_url,meeting_point,max_altitude_m,total_distance_km,includes,excludes,created_by) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,'trip',$9,$10,$11,$12,$13,$14,$15,$16,$17) RETURNING id::text",
        cid, "Pondicherry Beach & Heritage Walk", "Weekend trip to Pondy! French Quarter, Paradise Beach, Auroville & seafood.",
        "Pondicherry", now+timedelta(days=9), now+timedelta(days=10), 1999, 25, 2, "easy",
        "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=600&h=400&fit=crop",
        "Guindy Bus Stop - 5:30 AM", 0, 5,
        ["AC bus", "Homestay", "Breakfast & dinner", "Heritage guide", "Boat to Paradise Beach"],
        ["Lunch", "Personal shopping"], pid
    )
    pondyid = e["id"]
    for d in [
        (1, "Chennai to Pondy", "Drive to Pondy. French Quarter walk. Beaches.",
         "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=400",
         ["Morning: Depart 5:30 AM. Breakfast at Mahabalipuram.", "Afternoon: French Quarter heritage walk. French cafe lunch.", "Evening: Rock Beach sunset. Seafood dinner."]),
        (2, "Paradise Beach & Auroville", "Boat to Paradise Beach. Auroville. Return.",
         "https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?w=400",
         ["Morning: Beach yoga. Boat to Paradise Beach.", "Afternoon: Auroville & Matrimandir. Bakery lunch.", "Evening: Depart. Guindy by 8 PM."]),
    ]:
        await pool.execute(
            "INSERT INTO event_itinerary (event_id,day_number,title,description,image_url,activities) VALUES ($1,$2,$3,$4,$5,$6)",
            pondyid, d[0], d[1], d[2], d[3], d[4]
        )
    print("Added Pondicherry trip + itinerary")

    # Friendships
    naveen = await pool.fetchval("SELECT id::text FROM users WHERE username = 'naveen_d'")
    priya = await pool.fetchval("SELECT id::text FROM users WHERE username = 'priya.sharma'")
    rahul = await pool.fetchval("SELECT id::text FROM users WHERE username = 'rahul_k'")
    fcnt = await pool.fetchval("SELECT COUNT(*) FROM friendships")
    if fcnt == 0:
        await pool.execute("INSERT INTO friendships (sender_id,receiver_id,status) VALUES ($1,$2,'accepted')", naveen, priya)
        await pool.execute("INSERT INTO friendships (sender_id,receiver_id,status) VALUES ($1,$2,'accepted')", naveen, rahul)
        print("Added friendships")

    # Posts
    pcnt = await pool.fetchval("SELECT COUNT(*) FROM posts")
    if pcnt == 0:
        anitha = await pool.fetchval("SELECT id::text FROM users WHERE username = 'anitha.r'")
        karthik = await pool.fetchval("SELECT id::text FROM users WHERE username = 'karthik_s'")
        await pool.execute("INSERT INTO posts (user_id,caption,image_url) VALUES ($1,$2,$3)", priya, "Amazing sunrise at Marina Beach!", "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=600")
        await pool.execute("INSERT INTO posts (user_id,caption,image_url) VALUES ($1,$2,$3)", rahul, "Weekend cricket with the boys!", "https://images.unsplash.com/photo-1531415074968-036ba1b575da?w=600")
        await pool.execute("INSERT INTO posts (user_id,caption,image_url) VALUES ($1,$2,$3)", anitha, "Open mic night was incredible!", "https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=600")
        await pool.execute("INSERT INTO posts (user_id,caption,image_url) VALUES ($1,$2,$3)", karthik, "Captured this beauty during Yelagiri trek!", "https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=600")
        print("Added posts")

    print("\n=== ALL DONE ===")
    print("PARTNER: trek@strangermeet.com / trek@123 / @trekwithstrangers")
    print("USERS:")
    print("  naveen@strangermeet.com / naveen123 / @naveen_d")
    print("  priya@strangermeet.com / priya123 / @priya.sharma")
    print("  rahul@strangermeet.com / rahul123 / @rahul_k")
    print("  anitha@strangermeet.com / anitha123 / @anitha.r")
    print("  karthik@strangermeet.com / karthik123 / @karthik_s")
    await pool.close()

asyncio.run(fix())
