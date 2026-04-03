import { MapPin, Mail } from 'lucide-react';

export default function Footer() {
  return (
    <footer className="bg-[#f8f8f6] border-t border-gray-200">
      <div className="w-full max-w-6xl mx-auto px-6 lg:px-8 py-16">
        <div className="grid md:grid-cols-4 gap-10">
          {/* Brand */}
          <div>
            <a href="#" className="inline-block mb-4">
              <span className="text-[#1a1a1a] font-bold text-xl">
                Stranger<span className="text-[#4CAF50]">Meet</span>
              </span>
            </a>
            <p className="text-gray-500 text-sm leading-relaxed">
              Connect with strangers, make friends, explore together.
            </p>
          </div>

          {/* Quick Links */}
          <div>
            <h4 className="text-[#1a1a1a] font-semibold mb-4">Explore</h4>
            <ul className="space-y-2.5">
              <li><a href="#trips" className="text-gray-500 hover:text-gray-700 text-sm transition-colors">Destinations</a></li>
              <li><a href="#events" className="text-gray-500 hover:text-gray-700 text-sm transition-colors">Events</a></li>
              <li><a href="#why-us" className="text-gray-500 hover:text-gray-700 text-sm transition-colors">Why Choose Us</a></li>
            </ul>
          </div>

          {/* Company */}
          <div>
            <h4 className="text-[#1a1a1a] font-semibold mb-4">Company</h4>
            <ul className="space-y-2.5">
              <li><a href="#" className="text-gray-500 hover:text-gray-700 text-sm transition-colors">About Us</a></li>
              <li><a href="#" className="text-gray-500 hover:text-gray-700 text-sm transition-colors">Privacy Policy</a></li>
              <li><a href="#" className="text-gray-500 hover:text-gray-700 text-sm transition-colors">Terms of Service</a></li>
            </ul>
          </div>

          {/* Contact */}
          <div>
            <h4 className="text-[#1a1a1a] font-semibold mb-4">Contact</h4>
            <ul className="space-y-2.5">
              <li className="flex items-center gap-2 text-gray-500 text-sm">
                <Mail size={14} className="text-[#4CAF50] shrink-0" />
                support@strangermeet.com
              </li>
              <li className="flex items-center gap-2 text-gray-500 text-sm">
                <MapPin size={14} className="text-[#4CAF50] shrink-0" />
                Chennai, India
              </li>
            </ul>
          </div>
        </div>

        <div className="border-t border-gray-200 mt-12 pt-8 flex flex-col sm:flex-row items-center justify-between gap-4">
          <p className="text-gray-400 text-sm">
            &copy; {new Date().getFullYear()} StrangerMeet. All rights reserved.
          </p>
          <p className="text-gray-300 text-xs">
            Can't decide? Take our 2-minute quiz to find your perfect adventure
          </p>
        </div>
      </div>
    </footer>
  );
}
