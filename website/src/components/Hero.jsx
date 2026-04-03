import { useState } from 'react';
import { Search, MapPin, Calendar, CheckCircle, ArrowRight } from 'lucide-react';

export default function Hero() {
  const [location, setLocation] = useState('');

  const handleSearch = () => {
    if (location.trim()) {
      const el = document.getElementById('trips');
      if (el) el.scrollIntoView({ behavior: 'smooth' });
    }
  };

  return (
    <section className="relative min-h-screen flex flex-col items-center justify-center overflow-hidden">
      {/* Background with image */}
      <div className="absolute inset-0">
        <div
          className="w-full h-full bg-cover bg-center"
          style={{
            backgroundImage: `url('https://images.unsplash.com/photo-1506905925346-21bda4d32df4?q=80&w=1920&auto=format&fit=crop')`,
            backgroundColor: '#e8efe5',
          }}
        />
        <div className="absolute inset-0 bg-gradient-to-b from-white/70 via-white/40 to-white/90" />
        <div className="absolute bottom-0 left-0 right-0 h-40 bg-gradient-to-t from-white to-transparent" />
      </div>

      {/* Content */}
      <div className="relative z-10 w-full max-w-3xl mx-auto px-6 text-center pt-28 pb-16">
        {/* Badge */}
        <div className="flex justify-center mb-8">
          <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-white/80 backdrop-blur-sm border border-gray-200 shadow-sm">
            <CheckCircle size={16} className="text-[#4CAF50]" />
            <span className="text-gray-700 text-sm font-medium">BEST TRIP COMMUNITY IN 2025</span>
          </div>
        </div>

        {/* Main heading */}
        <h1 className="text-4xl sm:text-5xl lg:text-[64px] leading-[1.15] font-bold text-[#1a1a1a] mb-6">
          Turn Your{' '}
          <span style={{ fontFamily: "'Playfair Display', Georgia, serif" }} className="italic font-semibold">
            Travel Dreams
          </span>{' '}
          Into
          <br />
          Epic Adventures
        </h1>

        {/* Subtitle */}
        <p className="text-gray-500 text-lg lg:text-xl mb-14">
          Pay anytime, explore the world without any worries.
        </p>

        {/* Search card */}
        <div className="w-full max-w-2xl mx-auto">
          {/* Browser-style top bar */}
          <div className="bg-gray-100 rounded-t-2xl px-5 py-3 flex items-center gap-3 border border-b-0 border-gray-200">
            <div className="flex gap-1.5">
              <div className="w-3 h-3 rounded-full bg-red-400" />
              <div className="w-3 h-3 rounded-full bg-yellow-400" />
              <div className="w-3 h-3 rounded-full bg-green-400" />
            </div>
            <div className="flex-1 flex justify-center">
              <div className="bg-white rounded-full px-4 py-1 text-sm text-gray-400 border border-gray-200">
                StrangerMeet.com
              </div>
            </div>
          </div>

          {/* Search form */}
          <div className="bg-white rounded-b-2xl shadow-xl border border-gray-200 p-6 lg:p-8">
            <div className="flex flex-col sm:flex-row gap-4 items-end">
              {/* Location */}
              <div className="flex-1 w-full text-left">
                <label className="block text-sm font-semibold text-gray-800 mb-2">Location</label>
                <div className="relative">
                  <MapPin size={18} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
                  <input
                    type="text"
                    value={location}
                    onChange={(e) => setLocation(e.target.value)}
                    placeholder="Where do you want to explore?"
                    className="w-full pl-10 pr-4 py-3 rounded-xl border border-gray-200 bg-gray-50 text-gray-700 placeholder:text-gray-400 text-sm focus:outline-none focus:ring-2 focus:ring-[#4CAF50]/30 focus:border-[#4CAF50] transition-all"
                  />
                </div>
              </div>

              {/* Date */}
              <div className="flex-1 w-full text-left">
                <label className="block text-sm font-semibold text-gray-800 mb-2">Date</label>
                <div className="relative">
                  <Calendar size={18} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
                  <input
                    type="text"
                    placeholder="When are you free to travel?"
                    className="w-full pl-10 pr-4 py-3 rounded-xl border border-gray-200 bg-gray-50 text-gray-700 placeholder:text-gray-400 text-sm focus:outline-none focus:ring-2 focus:ring-[#4CAF50]/30 focus:border-[#4CAF50] transition-all"
                  />
                </div>
              </div>

              {/* Button */}
              <button
                onClick={handleSearch}
                className="w-full sm:w-auto px-6 py-3 bg-[#4CAF50] hover:bg-[#43A047] text-white font-semibold rounded-xl transition-all duration-200 hover:shadow-lg hover:shadow-[#4CAF50]/25 flex items-center justify-center gap-2 whitespace-nowrap shrink-0"
              >
                <Search size={18} />
                Start Your Journey
              </button>
            </div>

            <div className="mt-4 text-left">
              <span className="text-gray-400 text-sm">Not sure? </span>
              <a href="#trips" className="text-[#4CAF50] text-sm font-medium hover:underline inline-flex items-center gap-1">
                Let us help you choose <ArrowRight size={14} />
              </a>
            </div>
          </div>
        </div>

        {/* Trust badges */}
        <div className="flex flex-wrap justify-center gap-6 lg:gap-10 mt-10">
          <div className="flex items-center gap-2 text-gray-600 text-sm">
            <CheckCircle size={16} className="text-[#4CAF50]" />
            <span>No credit card required</span>
          </div>
          <div className="flex items-center gap-2 text-gray-600 text-sm">
            <CheckCircle size={16} className="text-[#4CAF50]" />
            <span>Free cancellation 30 days</span>
          </div>
          <div className="flex items-center gap-2 text-gray-600 text-sm">
            <CheckCircle size={16} className="text-[#4CAF50]" />
            <span>24/7 Support</span>
          </div>
        </div>
      </div>
    </section>
  );
}
