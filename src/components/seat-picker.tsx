import { cn } from "@/lib/utils.ts";
import { useTranslation } from "react-i18next";

type SeatPickerProps = {
  totalSeats: number;
  occupiedSeats: string[];
  selectedSeat: string | null;
  onSelect: (seat: string | null) => void;
  /** Bus type affects the seat layout columns: standard=4, mini=3, luxury=4 */
  busType?: string;
};

/**
 * Visual bus seat picker with rows.
 * Standard/luxury: 2+2 layout (4 seats per row)
 * Mini: 2+1 layout (3 seats per row)
 */
export default function SeatPicker({
  totalSeats,
  occupiedSeats,
  selectedSeat,
  onSelect,
  busType,
}: SeatPickerProps) {
  const { t } = useTranslation("common");
  const seatsPerRow = busType === "mini" ? 3 : 4;
  const leftCols = busType === "mini" ? 1 : 2;
  const rightCols = 2;
  const totalRows = Math.ceil(totalSeats / seatsPerRow);

  // Generate seats as sequential numbers: "1", "2", "3"...
  const allSeats: string[] = [];
  for (let i = 1; i <= totalSeats; i++) {
    allSeats.push(String(i));
  }

  const occupiedSet = new Set(occupiedSeats);

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-4 text-xs">
        <div className="flex items-center gap-1.5">
          <div className="w-4 h-4 rounded-sm border-2 border-muted-foreground/30 bg-muted" />
          <span className="text-muted-foreground">{t("seat_available", { defaultValue: "Libre" })}</span>
        </div>
        <div className="flex items-center gap-1.5">
          <div className="w-4 h-4 rounded-sm bg-destructive/20 border-2 border-destructive/40" />
          <span className="text-muted-foreground">{t("seat_occupied", { defaultValue: "Occupé" })}</span>
        </div>
        <div className="flex items-center gap-1.5">
          <div className="w-4 h-4 rounded-sm bg-primary border-2 border-primary" />
          <span className="text-muted-foreground">{t("seat_selected", { defaultValue: "Votre siège" })}</span>
        </div>
      </div>

      {/* Bus outline */}
      <div className="rounded-xl border-2 border-muted-foreground/20 p-3 bg-muted/30 max-w-[280px] mx-auto">
        {/* Driver indicator */}
        <div className="flex justify-end mb-3">
          <div className="w-8 h-8 rounded-full border-2 border-muted-foreground/30 flex items-center justify-center">
            <span className="text-[9px] text-muted-foreground font-medium">D</span>
          </div>
        </div>

        {/* Seat rows */}
        <div className="space-y-1.5">
          {Array.from({ length: totalRows }).map((_, rowIdx) => {
            const rowStart = rowIdx * seatsPerRow;
            const leftSeats = allSeats.slice(rowStart, rowStart + leftCols);
            const rightSeats = allSeats.slice(rowStart + leftCols, rowStart + seatsPerRow);

            return (
              <div key={rowIdx} className="flex items-center justify-center gap-3">
                {/* Left side */}
                <div className="flex gap-1">
                  {leftSeats.map((seat) => (
                    <SeatButton
                      key={seat}
                      seat={seat}
                      isOccupied={occupiedSet.has(seat)}
                      isSelected={selectedSeat === seat}
                      onSelect={onSelect}
                    />
                  ))}
                  {/* Fill empty space if last row has fewer seats on left */}
                  {leftSeats.length < leftCols &&
                    Array.from({ length: leftCols - leftSeats.length }).map((_, i) => (
                      <div key={`empty-l-${i}`} className="w-9 h-9" />
                    ))}
                </div>

                {/* Aisle */}
                <div className="w-4" />

                {/* Right side */}
                <div className="flex gap-1">
                  {rightSeats.map((seat) => (
                    <SeatButton
                      key={seat}
                      seat={seat}
                      isOccupied={occupiedSet.has(seat)}
                      isSelected={selectedSeat === seat}
                      onSelect={onSelect}
                    />
                  ))}
                  {rightSeats.length < rightCols &&
                    Array.from({ length: rightCols - rightSeats.length }).map((_, i) => (
                      <div key={`empty-r-${i}`} className="w-9 h-9" />
                    ))}
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {selectedSeat && (
        <p className="text-center text-sm font-medium text-primary">
          {t("seat_label", { defaultValue: "Siège" })} #{selectedSeat}
        </p>
      )}
    </div>
  );
}

function SeatButton({
  seat,
  isOccupied,
  isSelected,
  onSelect,
}: {
  seat: string;
  isOccupied: boolean;
  isSelected: boolean;
  onSelect: (seat: string | null) => void;
}) {
  return (
    <button
      type="button"
      disabled={isOccupied}
      onClick={() => onSelect(isSelected ? null : seat)}
      className={cn(
        "w-9 h-9 rounded-md text-[10px] font-bold transition-all flex items-center justify-center",
        isOccupied
          ? "bg-destructive/15 border-2 border-destructive/30 text-destructive/60 cursor-not-allowed"
          : isSelected
            ? "bg-primary border-2 border-primary text-primary-foreground scale-105 shadow-md cursor-pointer"
            : "bg-background border-2 border-muted-foreground/20 text-foreground hover:border-primary/60 hover:bg-primary/5 cursor-pointer"
      )}
    >
      {seat}
    </button>
  );
}
