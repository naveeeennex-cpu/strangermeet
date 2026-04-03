import { useState, useEffect } from 'react';
import { motion } from 'framer-motion';
import { MapPin, Calendar, Users, Clock, Star, ArrowRight, Flame } from 'lucide-react';

const API_BASE = 'https://strangermeet-production.up.railway.app/api';

function formatDate(dateStr) {
  const d = new Date(dateStr);
  return d.toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });
}

function EventCard({ event, index }) {
  const isTrip = event.event_type === 'trip';

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true }}
      transition={{ duration: 0.4, delay: index * 0.06 }}
      className="group bg-white rounded-2xl border border-gray-100 overflow-hidden hover:shadow-xl transition-all duration-300 hover:-translate-y-1"
    >
      {/* Image */}
      <div className="relative h-52 bg-gray-100 overflow-hidden">
        {event.image_url ? (
          <img
            src={event.image_url}
            alt={event.title}
            className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
          />
        ) : (
          <div className="w-full h-full bg-gradient-to-br from-green-50 to-emerald-100 flex items-center justify-center">
            <span className="text-5xl">{isTrip ? '\u26F0\uFE0F' : '\uD83C\uDFAA'}</span>
          </div>
        )}

        <div className="absolute inset-0 bg-gradient-to-t from-black/40 via-transparent to-transparent" />

        {/* Type badge */}
        <div className="absolute top-3 left-3">
          <span className={`px-3 py-1 rounded-full text-xs font-semibold backdrop-blur-sm ${
            isTrip ? 'bg-[#4CAF50]/90 text-white' : 'bg-white/90 text-gray-700'
          }`}>
            {isTrip ? 'Trip' : 'Event'}
          </span>
        </div>

        {/* Location on image */}
        {event.location && (
          <div className="absolute bottom-3 left-3 flex items-center gap-1 text-white text-sm">
            <MapPin size={14} />
            <span className="drop-shadow-md font-medium">{event.location}</span>
          </div>
        )}

        {/* Difficulty */}
        {isTrip && event.difficulty && (
          <div className="absolute top-3 right-3">
            <span className="px-2.5 py-1 rounded-full text-xs font-medium bg-white/90 text-gray-600 backdrop-blur-sm capitalize">
              {event.difficulty}
            </span>
          </div>
        )}
      </div>

      {/* Content */}
      <div className="p-5">
        <h3 className="text-[#1a1a1a] font-bold text-lg mb-2 line-clamp-1 group-hover:text-[#4CAF50] transition-colors">
          {event.title}
        </h3>

        {/* Rating + Meta row */}
        <div className="flex items-center flex-wrap gap-3 text-sm text-gray-500 mb-3">
          <div className="flex items-center gap-1">
            <Star size={14} className="text-yellow-400 fill-yellow-400" />
            <span className="font-medium text-gray-700">4.8</span>
          </div>
          {event.duration_days > 1 && (
            <>
              <span className="text-gray-300">|</span>
              <div className="flex items-center gap-1">
                <Clock size={14} />
                <span>{event.duration_days} days</span>
              </div>
            </>
          )}
          <span className="text-gray-300">|</span>
          <div className="flex items-center gap-1">
            <Users size={14} />
            <span>{event.participants_count || 0} people</span>
          </div>
        </div>

        {/* Date */}
        <div className="flex items-center gap-2 text-gray-400 text-sm mb-4">
          <Calendar size={14} />
          <span>{formatDate(event.date)}</span>
        </div>

        {/* Price + CTA */}
        <div className="flex items-center justify-between pt-4 border-t border-gray-100">
          <div>
            <div className="text-[#1a1a1a] font-bold text-lg">
              {event.price > 0 ? (
                <>From {'\u20B9'}{event.price.toLocaleString()}</>
              ) : (
                <span className="text-[#4CAF50]">Free</span>
              )}
            </div>
            {event.price > 0 && (
              <div className="text-gray-400 text-xs">per person</div>
            )}
          </div>

          <button className="px-5 py-2.5 bg-[#4CAF50] hover:bg-[#43A047] text-white text-sm font-semibold rounded-xl transition-all duration-200 hover:shadow-lg hover:shadow-[#4CAF50]/20">
            Let's Go
          </button>
        </div>

        {/* Community */}
        {event.community_name && (
          <div className="mt-3 flex items-center gap-2 pt-3 border-t border-gray-50">
            {event.community_image ? (
              <img src={event.community_image} alt="" className="w-5 h-5 rounded-full object-cover" />
            ) : (
              <div className="w-5 h-5 rounded-full bg-[#4CAF50]/10 flex items-center justify-center text-[10px] text-[#4CAF50] font-bold">
                {event.community_name[0]}
              </div>
            )}
            <span className="text-gray-400 text-xs">by {event.community_name}</span>
          </div>
        )}
      </div>
    </motion.div>
  );
}

export default function Events() {
  const [events, setEvents] = useState([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState('all');

  useEffect(() => {
    fetchEvents();
  }, []);

  async function fetchEvents() {
    try {
      const res = await fetch(`${API_BASE}/communities/explore/public-events?limit=50`);
      if (res.ok) {
        const data = await res.json();
        setEvents(data);
      }
    } catch (err) {
      console.error('Failed to fetch events:', err);
    } finally {
      setLoading(false);
    }
  }

  const filtered = filter === 'all' ? events : events.filter(e => e.event_type === filter);
  const trips = events.filter(e => e.event_type === 'trip');
  const eventsOnly = events.filter(e => e.event_type !== 'trip');

  return (
    <section id="trips" className="py-20 lg:py-28 bg-white">
      <div className="w-full max-w-6xl mx-auto px-6 lg:px-8">
        {/* Header */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          className="text-center mb-14"
        >
          <div className="flex justify-center mb-6">
            <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-white border border-gray-200 shadow-sm">
              <Flame size={16} className="text-orange-500" />
              <span className="text-gray-600 text-sm font-semibold tracking-wider uppercase">Most Popular Adventures</span>
            </div>
          </div>

          <h2 className="text-3xl sm:text-4xl lg:text-5xl font-bold text-[#1a1a1a] mb-4">
            Adventures{' '}
            <span style={{ fontFamily: "'Playfair Display', Georgia, serif" }} className="italic font-semibold">That Will Change</span>
            <br />Your Life
          </h2>
          <p className="text-gray-500 text-lg max-w-xl mx-auto">
            From ancient ruins to pristine beaches, discover the destinations that our travelers can't stop talking about.
          </p>
        </motion.div>

        {/* Filter tabs */}
        <div className="flex justify-center gap-2 mb-12">
          {[
            { key: 'all', label: 'All' },
            { key: 'trip', label: 'Trips' },
            { key: 'event', label: 'Events' },
          ].map(f => (
            <button
              key={f.key}
              onClick={() => setFilter(f.key)}
              className={`px-5 py-2.5 rounded-full text-sm font-medium transition-all duration-200 ${
                filter === f.key
                  ? 'bg-[#1a1a1a] text-white shadow-md'
                  : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
              }`}
            >
              {f.label}
            </button>
          ))}
        </div>

        {/* Cards */}
        {loading ? (
          <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-6">
            {Array.from({ length: 6 }).map((_, i) => (
              <div key={i} className="bg-white rounded-2xl border border-gray-100 overflow-hidden animate-pulse">
                <div className="h-52 bg-gray-100" />
                <div className="p-5 space-y-3">
                  <div className="h-5 bg-gray-100 rounded w-3/4" />
                  <div className="h-4 bg-gray-50 rounded w-1/2" />
                  <div className="h-4 bg-gray-50 rounded w-2/3" />
                </div>
              </div>
            ))}
          </div>
        ) : filtered.length > 0 ? (
          <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-6">
            {filtered.map((event, i) => (
              <EventCard key={event.id} event={event} index={i} />
            ))}
          </div>
        ) : (
          <div className="text-center py-20">
            <span className="text-6xl block mb-4">{'\uD83C\uDFD4\uFE0F'}</span>
            <h3 className="text-gray-400 text-xl font-medium mb-2">No events yet</h3>
            <p className="text-gray-300">Check back soon for new adventures!</p>
          </div>
        )}

        {/* CTA button */}
        {filtered.length > 0 && (
          <div className="text-center mt-12">
            <button className="inline-flex items-center gap-2 px-8 py-4 bg-[#4CAF50] hover:bg-[#43A047] text-white font-semibold rounded-full transition-all duration-200 hover:shadow-xl hover:shadow-[#4CAF50]/20 text-sm">
              Explore all Destinations
              <ArrowRight size={18} />
            </button>
          </div>
        )}
      </div>
    </section>
  );
}
