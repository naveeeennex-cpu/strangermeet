import asyncio
import asyncpg
from datetime import datetime, timedelta

async def seed():
    pool = await asyncpg.create_pool(
        'postgresql://postgres.lrgjntwdntwqjnewarmk:Naveeeen2026@aws-1-ap-northeast-2.pooler.supabase.com:6543/postgres',
        statement_cache_size=0
    )

    # Fix Hampta Pass Trek to be a trip
    await pool.execute("""
        UPDATE community_events SET
            event_type = 'trip',
            duration_days = 5,
            difficulty = 'moderate',
            max_altitude_m = 4270,
            total_distance_km = 26,
            includes = ARRAY['Camping equipment', 'All meals', 'Guide & support staff', 'Permits', 'First aid kit'],
            excludes = ARRAY['Travel to Manali', 'Personal equipment', 'Travel insurance', 'Tips'],
            meeting_point = 'Mall Road, Manali - 9:00 AM',
            end_date = date + interval '5 days'
        WHERE title LIKE '%Hampta%'
    """)
    print("Fixed Hampta Pass Trek")

    # Get trek community
    trek = await pool.fetchrow("SELECT id, created_by FROM communities WHERE name = 'Trek With Strangers'")
    trek_id = str(trek['id'])
    admin_id = str(trek['created_by'])

    trips = [
        {
            'title': 'Kedarkantha Winter Trek',
            'description': 'A stunning winter trek through snow-covered trails in Uttarakhand. Perfect for beginners who want to experience snow trekking. Summit at 12,500 ft offers 360-degree panoramic views.',
            'location': 'Sankri, Uttarakhand',
            'price': 7499.0,
            'slots': 20,
            'image_url': 'https://images.unsplash.com/photo-1486911278844-a81c5267e227?w=800&h=600&fit=crop',
            'event_type': 'trip',
            'duration_days': 6,
            'difficulty': 'easy',
            'max_altitude_m': 3810.0,
            'total_distance_km': 20.0,
            'includes': ['Camping gear', 'All meals', 'Trek leader', 'Permits', 'Medical kit'],
            'excludes': ['Travel to Sankri', 'Personal gear', 'Insurance'],
            'meeting_point': 'Sankri Base Camp - 10:00 AM',
            'days_offset': 14,
        },
        {
            'title': 'Valley of Flowers Trek',
            'description': 'Explore the UNESCO World Heritage Site bursting with alpine flowers. A magical journey through one of the most beautiful valleys in India.',
            'location': 'Govindghat, Uttarakhand',
            'price': 11999.0,
            'slots': 15,
            'image_url': 'https://images.unsplash.com/photo-1501785888041-af3ef285b470?w=800&h=600&fit=crop',
            'event_type': 'trip',
            'duration_days': 6,
            'difficulty': 'moderate',
            'max_altitude_m': 3658.0,
            'total_distance_km': 38.0,
            'includes': ['Accommodation', 'All meals', 'Guide', 'Permits', 'Mule support'],
            'excludes': ['Travel to Govindghat', 'Personal equipment', 'Tips'],
            'meeting_point': 'Govindghat Helipad - 8:00 AM',
            'days_offset': 21,
        },
        {
            'title': 'Triund Trek - Weekend Getaway',
            'description': 'Perfect weekend escape! Easy overnight trek above McLeodganj with stunning views of the Dhauladhar range. Camp under the stars.',
            'location': 'McLeodganj, Himachal Pradesh',
            'price': 2999.0,
            'slots': 25,
            'image_url': 'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=800&h=600&fit=crop',
            'event_type': 'trip',
            'duration_days': 2,
            'difficulty': 'easy',
            'max_altitude_m': 2850.0,
            'total_distance_km': 9.0,
            'includes': ['Camping gear', 'Dinner & breakfast', 'Guide'],
            'excludes': ['Travel to McLeodganj', 'Lunch', 'Personal gear'],
            'meeting_point': 'Gallu Devi Temple - 7:00 AM',
            'days_offset': 7,
        },
        {
            'title': 'Goa Beach Meetup Weekend',
            'description': 'Chill beach weekend with strangers! Hidden beaches, water sports, beach volleyball, bonfire party, and amazing seafood.',
            'location': 'Palolem Beach, Goa',
            'price': 4999.0,
            'slots': 30,
            'image_url': 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800&h=600&fit=crop',
            'event_type': 'event',
            'duration_days': 3,
            'difficulty': 'easy',
            'max_altitude_m': 0.0,
            'total_distance_km': 0.0,
            'includes': ['Accommodation', 'Breakfast', 'Water sports', 'Bonfire party'],
            'excludes': ['Travel to Goa', 'Lunch & dinner', 'Personal expenses'],
            'meeting_point': 'Palolem Beach Shack #7 - 4:00 PM',
            'days_offset': 10,
        },
        {
            'title': 'Bangalore Tech & Hike Meetup',
            'description': 'Morning hike at Nandi Hills followed by a tech networking brunch. Meet fellow tech enthusiasts in a relaxed outdoor setting.',
            'location': 'Nandi Hills, Bangalore',
            'price': 0.0,
            'slots': 40,
            'image_url': 'https://images.unsplash.com/photo-1551632811-561732d1e306?w=800&h=600&fit=crop',
            'event_type': 'event',
            'duration_days': 1,
            'difficulty': 'easy',
            'max_altitude_m': 1478.0,
            'total_distance_km': 5.0,
            'includes': ['Brunch', 'Transport from Bangalore'],
            'excludes': ['Personal expenses'],
            'meeting_point': 'Majestic Bus Stand - 5:00 AM',
            'days_offset': 5,
        },
    ]

    for t in trips:
        start_date = datetime.now() + timedelta(days=t['days_offset'])
        end_date = start_date + timedelta(days=t['duration_days'])
        await pool.execute(
            """INSERT INTO community_events
               (community_id, title, description, location, date, end_date, price, slots, image_url,
                created_by, event_type, duration_days, difficulty, max_altitude_m, total_distance_km,
                includes, excludes, meeting_point)
               VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18)""",
            trek_id, t['title'], t['description'], t['location'],
            start_date, end_date,
            t['price'], t['slots'], t['image_url'], admin_id,
            t['event_type'], t['duration_days'], t['difficulty'],
            t['max_altitude_m'], t['total_distance_km'],
            t['includes'], t['excludes'], t['meeting_point']
        )
        print(f"Added: {t['title']} ({t['event_type']})")

    print("\nDone! All trips and events seeded.")
    await pool.close()

asyncio.run(seed())
