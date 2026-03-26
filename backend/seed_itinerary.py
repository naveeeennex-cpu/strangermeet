import asyncio
import asyncpg

async def seed():
    pool = await asyncpg.create_pool(
        'postgresql://postgres.lrgjntwdntwqjnewarmk:Naveeeen2026@aws-1-ap-northeast-2.pooler.supabase.com:6543/postgres',
        statement_cache_size=0
    )

    # Get all trip events
    trips = await pool.fetch("SELECT id, title, duration_days FROM community_events WHERE event_type = 'trip'")
    print(f"Found {len(trips)} trips")

    itineraries = {
        'Hampta Pass': [
            {'day': 1, 'title': 'Manali to Jobra', 'description': 'Drive to Jobra via Prini village. Short acclimatization walk around the campsite.',
             'image_url': 'https://images.unsplash.com/photo-1544735716-392fe2489ffa?w=600&h=400&fit=crop',
             'activities': ['Morning: Arrive in Manali and meet the group at Mall Road. Breakfast together.', 'Afternoon: Drive to Jobra (3150m). Set up camp and explore the meadows.', 'Evening: Welcome dinner and trek briefing by the guide. Early sleep for Day 2.'],
             'accommodation': 'Alpine tents at Jobra campsite (3150m)', 'elevation': '3150m', 'distance': '3 km trek', 'meals': 'Lunch, Dinner'},
            {'day': 2, 'title': 'Jobra to Balu Ka Ghera', 'description': 'Trek through lush meadows and cross streams. Stunning views of Deo Tibba.',
             'image_url': 'https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=600&h=400&fit=crop',
             'activities': ['Morning: Early breakfast. Begin trek through pine forests and open meadows.', 'Afternoon: Cross glacial streams. Reach Balu Ka Ghera (3660m). Lunch at camp.', 'Evening: Hot soup and bonfire. Share stories with fellow trekkers.'],
             'accommodation': 'Tents at Balu Ka Ghera (3660m)', 'elevation': '3660m', 'distance': '7 km', 'meals': 'Breakfast, Lunch, Dinner'},
            {'day': 3, 'title': 'Balu Ka Ghera to Siagoru via Hampta Pass', 'description': 'The big day! Cross the Hampta Pass at 4270m. Dramatic landscape change from green to barren.',
             'image_url': 'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=600&h=400&fit=crop',
             'activities': ['Morning: Early start at 5 AM. Steep climb to Hampta Pass (4270m). Summit photos!', 'Afternoon: Descend to Siagoru (3600m) on the Lahaul side. Incredible moonscape views.', 'Evening: Celebrate crossing the pass! Special dinner at camp.'],
             'accommodation': 'Tents at Siagoru (3600m)', 'elevation': '4270m (pass)', 'distance': '8 km', 'meals': 'Breakfast, Lunch, Dinner'},
            {'day': 4, 'title': 'Siagoru to Chatru', 'description': 'Descend along the Chandra river to Chatru. Easy walk through stunning valley.',
             'image_url': 'https://images.unsplash.com/photo-1486911278844-a81c5267e227?w=600&h=400&fit=crop',
             'activities': ['Morning: Relaxed breakfast. Begin descent along the river valley.', 'Afternoon: Reach Chatru (3360m). Optional visit to Chandratal if weather permits.', 'Evening: Last night camping. Group photo session and farewell dinner.'],
             'accommodation': 'Tents at Chatru (3360m)', 'elevation': '3360m', 'distance': '6 km', 'meals': 'Breakfast, Lunch, Dinner'},
            {'day': 5, 'title': 'Chatru to Manali', 'description': 'Drive back to Manali via Rohtang. Certificate distribution and farewell.',
             'image_url': 'https://images.unsplash.com/photo-1551632811-561732d1e306?w=600&h=400&fit=crop',
             'activities': ['Morning: Breakfast and pack up. Drive to Manali via Rohtang tunnel.', 'Afternoon: Arrive Manali by 2 PM. Certificate distribution. Free time for shopping.', 'Evening: Farewell lunch. Trek ends. New friendships begin!'],
             'accommodation': 'N/A - Trek ends', 'elevation': '2050m', 'distance': 'Drive', 'meals': 'Breakfast, Lunch'},
        ],
        'Kedarkantha': [
            {'day': 1, 'title': 'Dehradun to Sankri', 'description': 'Scenic drive through Mussoorie and Purola to Sankri base village.',
             'image_url': 'https://images.unsplash.com/photo-1486911278844-a81c5267e227?w=600&h=400&fit=crop',
             'activities': ['Morning: Pick up from Dehradun ISBT at 7 AM. Drive through Mussoorie.', 'Afternoon: Lunch stop at Purola. Continue to Sankri (1920m).', 'Evening: Check into homestay. Trek briefing and gear check.'],
             'accommodation': 'Homestay in Sankri (1920m)', 'elevation': '1920m', 'distance': 'Drive 220 km', 'meals': 'Lunch, Dinner'},
            {'day': 2, 'title': 'Sankri to Juda Ka Talab', 'description': 'Trek through beautiful oak and pine forests to a frozen lake.',
             'image_url': 'https://images.unsplash.com/photo-1501785888041-af3ef285b470?w=600&h=400&fit=crop',
             'activities': ['Morning: Breakfast at homestay. Begin trek through dense oak forest.', 'Afternoon: Arrive at Juda Ka Talab (2700m). Set up camp near the frozen lake.', 'Evening: Explore the beautiful frozen lake. Hot dinner by campfire.'],
             'accommodation': 'Tents near Juda Ka Talab (2700m)', 'elevation': '2700m', 'distance': '4 km', 'meals': 'Breakfast, Lunch, Dinner'},
            {'day': 3, 'title': 'Juda Ka Talab to Kedarkantha Base', 'description': 'Short trek to the base camp through snow-covered meadows.',
             'image_url': 'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=600&h=400&fit=crop',
             'activities': ['Morning: Leisurely breakfast. Short trek through snowy trails.', 'Afternoon: Reach base camp (3400m). Acclimatization walk. Play in the snow!', 'Evening: Early dinner. Prepare for summit day. Sleep by 7 PM.'],
             'accommodation': 'Tents at Kedarkantha Base (3400m)', 'elevation': '3400m', 'distance': '3 km', 'meals': 'Breakfast, Lunch, Dinner'},
            {'day': 4, 'title': 'Summit Day - Kedarkantha Peak', 'description': 'The summit push! 360-degree views of Swargarohini, Bandarpoonch, and Kala Nag peaks.',
             'image_url': 'https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=600&h=400&fit=crop',
             'activities': ['Morning: Wake up at 3 AM. Start summit climb at 4 AM with headlamps.', 'Afternoon: Reach summit (3810m) by sunrise! Breathtaking 360° views. Descend to Juda Ka Talab.', 'Evening: Celebration dinner! Share summit photos with the group.'],
             'accommodation': 'Tents at Juda Ka Talab (2700m)', 'elevation': '3810m (summit)', 'distance': '7 km', 'meals': 'Breakfast, Lunch, Dinner'},
            {'day': 5, 'title': 'Juda Ka Talab to Sankri', 'description': 'Descend back to Sankri. Certificate distribution.',
             'image_url': 'https://images.unsplash.com/photo-1544735716-392fe2489ffa?w=600&h=400&fit=crop',
             'activities': ['Morning: Pack up camp. Easy descent back to Sankri.', 'Afternoon: Arrive Sankri. Hot shower! Certificate distribution.', 'Evening: Farewell dinner at homestay. Exchange contacts with new friends.'],
             'accommodation': 'Homestay in Sankri', 'elevation': '1920m', 'distance': '7 km', 'meals': 'Breakfast, Lunch, Dinner'},
            {'day': 6, 'title': 'Sankri to Dehradun', 'description': 'Drive back to Dehradun. Trek concludes.',
             'image_url': 'https://images.unsplash.com/photo-1551632811-561732d1e306?w=600&h=400&fit=crop',
             'activities': ['Morning: Breakfast and depart for Dehradun by 7 AM.', 'Afternoon: Arrive Dehradun by 5 PM. Trek officially ends.', 'Evening: Head home with amazing memories and lifelong friends!'],
             'accommodation': 'N/A - Trek ends', 'elevation': '640m', 'distance': 'Drive 220 km', 'meals': 'Breakfast'},
        ],
        'Valley of Flowers': [
            {'day': 1, 'title': 'Haridwar to Govindghat', 'description': 'Scenic drive along the Alaknanda river to Govindghat.',
             'image_url': 'https://images.unsplash.com/photo-1501785888041-af3ef285b470?w=600&h=400&fit=crop',
             'activities': ['Morning: Depart Haridwar at 6 AM. Drive through Rishikesh and Devprayag.', 'Afternoon: Lunch at Joshimath. Continue to Govindghat (1800m).', 'Evening: Check into hotel. Brief about the trek ahead.'],
             'accommodation': 'Hotel in Govindghat (1800m)', 'elevation': '1800m', 'distance': 'Drive 275 km', 'meals': 'Lunch, Dinner'},
            {'day': 2, 'title': 'Govindghat to Ghangaria', 'description': 'Trek along the Pushpawati river to the base village of Ghangaria.',
             'image_url': 'https://images.unsplash.com/photo-1486911278844-a81c5267e227?w=600&h=400&fit=crop',
             'activities': ['Morning: Cross Govindghat bridge. Begin trek along the Lakshman Ganga.', 'Afternoon: Stop at waterfalls along the way. Reach Ghangaria (3050m).', 'Evening: Rest and prepare for Valley of Flowers visit.'],
             'accommodation': 'Guesthouse in Ghangaria (3050m)', 'elevation': '3050m', 'distance': '9 km', 'meals': 'Breakfast, Lunch, Dinner'},
            {'day': 3, 'title': 'Valley of Flowers Exploration', 'description': 'Full day exploring the UNESCO World Heritage Valley of Flowers.',
             'image_url': 'https://images.unsplash.com/photo-1490750967868-88aa4f44baee?w=600&h=400&fit=crop',
             'activities': ['Morning: Enter Valley of Flowers National Park. Guided botanical walk.', 'Afternoon: Explore deeper into the valley. 600+ species of wildflowers! Photography session.', 'Evening: Return to Ghangaria. Share photos over dinner.'],
             'accommodation': 'Guesthouse in Ghangaria', 'elevation': '3658m', 'distance': '8 km (round trip)', 'meals': 'Breakfast, Packed Lunch, Dinner'},
            {'day': 4, 'title': 'Hemkund Sahib & Return', 'description': 'Visit the sacred Hemkund Sahib lake and trek back to Ghangaria.',
             'image_url': 'https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=600&h=400&fit=crop',
             'activities': ['Morning: Early trek to Hemkund Sahib (4329m). Visit the sacred glacial lake.', 'Afternoon: Descend back to Ghangaria. Rest and pack.', 'Evening: Last evening in the mountains. Group dinner.'],
             'accommodation': 'Guesthouse in Ghangaria', 'elevation': '4329m', 'distance': '12 km (round trip)', 'meals': 'Breakfast, Lunch, Dinner'},
            {'day': 5, 'title': 'Ghangaria to Govindghat', 'description': 'Descend to Govindghat and drive to Joshimath.',
             'image_url': 'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=600&h=400&fit=crop',
             'activities': ['Morning: Breakfast and begin descent to Govindghat.', 'Afternoon: Drive to Joshimath. Check into hotel.', 'Evening: Farewell dinner and certificate distribution.'],
             'accommodation': 'Hotel in Joshimath', 'elevation': '1800m', 'distance': '9 km trek + drive', 'meals': 'Breakfast, Lunch, Dinner'},
            {'day': 6, 'title': 'Joshimath to Haridwar', 'description': 'Drive back to Haridwar. Trek concludes.',
             'image_url': 'https://images.unsplash.com/photo-1551632811-561732d1e306?w=600&h=400&fit=crop',
             'activities': ['Morning: Depart Joshimath at 7 AM.', 'Afternoon: Arrive Haridwar by 5 PM. Trek ends.', 'Evening: Head home with unforgettable memories!'],
             'accommodation': 'N/A - Trek ends', 'elevation': '314m', 'distance': 'Drive 275 km', 'meals': 'Breakfast'},
        ],
        'Triund': [
            {'day': 1, 'title': 'McLeodganj to Triund', 'description': 'Trek through rhododendron forests to the stunning Triund ridge.',
             'image_url': 'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=600&h=400&fit=crop',
             'activities': ['Morning: Meet at Gallu Devi Temple at 7 AM. Begin trek through forests.', 'Afternoon: Reach Triund (2850m). Set up camp. Enjoy panoramic Dhauladhar views.', 'Evening: Sunset photography. Bonfire under the stars. Dinner at camp.'],
             'accommodation': 'Tents at Triund (2850m)', 'elevation': '2850m', 'distance': '4.5 km', 'meals': 'Lunch, Dinner'},
            {'day': 2, 'title': 'Triund Sunrise & Return', 'description': 'Catch the magical sunrise over the Dhauladhar range and descend.',
             'image_url': 'https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=600&h=400&fit=crop',
             'activities': ['Morning: Wake up for sunrise at 5 AM. Breakfast with mountain views.', 'Afternoon: Pack up and descend to McLeodganj by noon.', 'Evening: Free time to explore McLeodganj. Trek ends!'],
             'accommodation': 'N/A - Trek ends', 'elevation': '2082m', 'distance': '4.5 km', 'meals': 'Breakfast'},
        ],
    }

    for trip in trips:
        trip_id = str(trip['id'])
        title = trip['title']

        # Match itinerary by keyword
        matched_key = None
        for key in itineraries:
            if key.lower() in title.lower():
                matched_key = key
                break

        if not matched_key:
            print(f"No itinerary match for: {title}")
            continue

        days = itineraries[matched_key]

        # Delete existing itinerary
        await pool.execute("DELETE FROM event_itinerary WHERE event_id = $1", trip_id)

        for day in days:
            # Parse numeric values from strings like "3150m" -> 3150.0
            elev_str = day.get('elevation', '0')
            elev = float(''.join(c for c in elev_str if c.isdigit() or c == '.') or '0')
            dist_str = day.get('distance', '0')
            dist = float(''.join(c for c in dist_str if c.isdigit() or c == '.') or '0')
            await pool.execute(
                """INSERT INTO event_itinerary
                   (event_id, day_number, title, description, activities, accommodation, elevation_m, distance_km, meals_included)
                   VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)""",
                trip_id, day['day'], day['title'], day['description'],
                day['activities'],
                day.get('accommodation', ''), elev, dist,
                [m.strip() for m in day.get('meals', '').split(',') if m.strip()]
            )

        print(f"Added {len(days)} days itinerary for: {title}")

    print("\nDone! All itineraries seeded.")
    await pool.close()

asyncio.run(seed())
