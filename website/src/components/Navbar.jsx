import { useState, useEffect } from 'react';
import { Menu, X, LogIn } from 'lucide-react';

export default function Navbar() {
  const [scrolled, setScrolled] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 50);
    window.addEventListener('scroll', onScroll);
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  return (
    <nav
      className={`fixed top-0 left-0 right-0 z-50 transition-all duration-300 ${
        scrolled
          ? 'bg-white/95 backdrop-blur-md shadow-sm'
          : 'bg-white/80 backdrop-blur-sm'
      }`}
    >
      <div className="w-full max-w-6xl mx-auto px-6 lg:px-8">
        <div className="flex items-center justify-between h-16 lg:h-[72px]">
          {/* Logo */}
          <a href="#" className="flex items-center gap-1 shrink-0">
            <span className="text-[#1a1a1a] font-bold text-xl tracking-tight">
              Stranger<span className="text-[#4CAF50]">Meet</span>
            </span>
            <span className="text-gray-400 text-[10px] align-super ml-0.5">TM</span>
          </a>

          {/* Center nav */}
          <div className="hidden md:flex items-center gap-1">
            <a href="#trips" className="px-4 py-2 rounded-full bg-[#1a1a1a] text-white text-sm font-medium">
              Destinations
            </a>
            <a href="#trips" className="px-4 py-2 text-gray-600 hover:text-gray-900 text-sm font-medium">
              Events
            </a>
            <a href="#why-us" className="px-4 py-2 text-gray-600 hover:text-gray-900 text-sm font-medium">
              Why Us
            </a>
          </div>

          {/* Right side */}
          <div className="hidden md:flex items-center gap-4 shrink-0">
            <a href="#" className="text-gray-600 hover:text-gray-900 text-sm font-medium flex items-center gap-1.5">
              <LogIn size={16} />
              Login
            </a>
          </div>

          {/* Mobile toggle */}
          <button
            className="md:hidden text-gray-700"
            onClick={() => setMobileOpen(!mobileOpen)}
          >
            {mobileOpen ? <X size={24} /> : <Menu size={24} />}
          </button>
        </div>
      </div>

      {/* Mobile menu */}
      {mobileOpen && (
        <div className="md:hidden bg-white border-t border-gray-100">
          <div className="px-6 py-4 space-y-3">
            <a href="#trips" className="block text-gray-700 hover:text-gray-900 py-2 text-sm font-medium" onClick={() => setMobileOpen(false)}>Destinations</a>
            <a href="#trips" className="block text-gray-700 hover:text-gray-900 py-2 text-sm font-medium" onClick={() => setMobileOpen(false)}>Events</a>
            <a href="#why-us" className="block text-gray-700 hover:text-gray-900 py-2 text-sm font-medium" onClick={() => setMobileOpen(false)}>Why Us</a>
            <a href="#" className="block text-gray-700 hover:text-gray-900 py-2 text-sm font-medium">Login</a>
          </div>
        </div>
      )}
    </nav>
  );
}
