import { motion } from 'framer-motion';
import { Compass, CreditCard, Users } from 'lucide-react';

const features = [
  {
    icon: Compass,
    title: 'Expert Local Guides',
    description:
      'Our passionate local guides don\'t just show you places, they share stories, culture, and hidden gems that transform your journey into an authentic adventure.',
    badge: 'Average guide rating: 4.9/5',
    badgeEmoji: '\u2B50',
  },
  {
    icon: CreditCard,
    title: 'Flexible Payment Plans',
    description:
      'Don\'t let budget hold you back. Split your dream trip into manageable monthly payments with 0% interest. Start planning today, travel when you\'re ready.',
    badge: null,
    featured: true,
  },
  {
    icon: Users,
    title: 'Solo-Friendly Groups',
    description:
      '85% of our travelers are solo adventurers who become lifelong friends. Join small groups (8-16 people) of like-minded explorers from around the world.',
    badge: 'Join 500+ solo travelers',
    badgeEmoji: '\uD83C\uDF0D',
  },
];

export default function WhyChooseUs() {
  return (
    <section id="why-us" className="py-20 lg:py-28 bg-[#f8f8f6]">
      <div className="w-full max-w-6xl mx-auto px-6 lg:px-8">
        {/* Header */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          className="text-center mb-16"
        >
          <div className="flex justify-center mb-6">
            <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-white border border-gray-200 shadow-sm">
              <span className="text-lg">{'\uD83C\uDF92'}</span>
              <span className="text-gray-600 text-sm font-semibold tracking-wider uppercase">Why Choose Us</span>
            </div>
          </div>

          <h2 className="text-3xl sm:text-4xl lg:text-5xl font-bold text-[#1a1a1a] mb-4">
            Why 500+{' '}
            <span style={{ fontFamily: "'Playfair Display', Georgia, serif" }} className="italic font-semibold">Travelers</span>
            <br />Choose Us
          </h2>

          <p className="text-gray-500 text-lg max-w-xl mx-auto">
            We've perfected the art of group travel for solo adventurers. Here's what makes us different.
          </p>
        </motion.div>

        {/* Feature cards */}
        <div className="grid md:grid-cols-3 gap-6 lg:gap-8">
          {features.map((feature, i) => (
            <motion.div
              key={i}
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ delay: i * 0.1 }}
              className={`rounded-2xl p-8 text-center ${
                feature.featured
                  ? 'bg-white shadow-xl border border-gray-100'
                  : 'bg-white/60 border border-gray-100'
              }`}
            >
              <div className="w-14 h-14 rounded-2xl bg-gray-100 flex items-center justify-center mb-6 mx-auto">
                <feature.icon size={26} className="text-gray-700" />
              </div>

              <h3 className="text-xl font-bold text-[#1a1a1a] mb-3">{feature.title}</h3>
              <p className="text-gray-500 text-sm leading-relaxed mb-5">{feature.description}</p>

              {feature.badge && (
                <div className="inline-flex items-center gap-1.5 px-4 py-2 rounded-full bg-[#FFF3F0] text-[#E8604C] text-sm font-medium">
                  {feature.badge} {feature.badgeEmoji}
                </div>
              )}
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
}
