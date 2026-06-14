import SupabaseTripSearch from "@/pages/traveler/SupabaseTripSearch.tsx";
import HomeStationsMap from "@/pages/landing/HomeStationsMap.tsx";

/** Bloc landing : filtres + voyages disponibles (liste en accordéon). */
export default function LandingTravelSection() {
  return (
    <section id="home-trip-search" className="border-y bg-muted/30 scroll-mt-16">
      <div className="max-w-6xl mx-auto px-4 sm:px-6 py-6 md:py-8 space-y-8">
        <SupabaseTripSearch embedded hideTitle accordionResults />
        <HomeStationsMap embedded />
      </div>
    </section>
  );
}
