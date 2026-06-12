import SupabaseTripSearch from "@/pages/traveler/SupabaseTripSearch.tsx";
import HomeStationsMap from "@/pages/landing/HomeStationsMap.tsx";

/** Bloc landing : recherche trajets (filtres + résultats) puis carte des gares. */
export default function LandingTravelSection() {
  return (
    <section id="home-trip-search" className="border-y bg-muted/30 scroll-mt-16">
      <div className="max-w-6xl mx-auto px-4 sm:px-6 py-8 md:py-10 space-y-10">
        <SupabaseTripSearch embedded />
        <div className="border-t pt-10" />
        <HomeStationsMap embedded />
      </div>
    </section>
  );
}
