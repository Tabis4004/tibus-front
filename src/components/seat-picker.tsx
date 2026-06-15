import { cn } from "@/lib/utils.ts";
import { useTranslation } from "react-i18next";

type SeatPickerProps = {
  totalSeats: number;
  occupiedSeats: string[];
  /** Bus type affects the seat layout columns: standard=4, mini=3, luxury=4 */
  busType?: string;
  /** Single-seat mode (default) */
  selectedSeat?: string | null;
  onSelect?: (seat: string | null) => void;
  /** Multi-seat mode */
  selectedSeats?: string[];
  maxSelections?: number;
  onSelectMultiple?: (seats: string[]) => void;
};

/**
 * Visual bus seat picker with rows.
 * Standard/luxury: 2+2 layout (4 seats per row)
 * Mini: 2+1 layout (3 seats per row)
 */
export default function SeatPicker({
  totalSeats,
  occupiedSeats,
  selectedSeat = null,
  onSelect,
  selectedSeats = [],
  maxSelections,
  onSelectMultiple,
  busType,
}: SeatPickerProps) {
  const { t } = useTranslation("common");
  const isMultiple = Boolean(onSelectMultiple);
  const selectedSet = new Set(isMultiple ? selectedSeats : selectedSeat ? [selectedSeat] : []);
  const seatsPerRow = busType === "mini" ? 3 : 4;
  const leftCols = busType === "mini" ? 1 : 2;
  const rightCols = 2;
  const totalRows = Math.ceil(totalSeats / seatsPerRow);

  const allSeats: string[] = [];
  for (let i = 1; i <= totalSeats; i++) {
    allSeats.push(String(i));
  }

  const occupiedSet = new Set(occupiedSeats);

  const handleSeatClick = (seat: string) => {
    const isSelected = selectedSet.has(seat);
    if (isMultiple && onSelectMultiple) {
      if (isSelected) {
        onSelectMultiple(selectedSeats.filter((value) => value !== seat));
        return;
      }
      const limit = maxSelections ?? selectedSeats.length + 1;
      if (selectedSeats.length >= limit) return;
      onSelectMultiple(
        [...selectedSeats, seat].sort((a, b) => Number(a) - Number(b)),
      );
      return;
    }
    onSelect?.(isSelected ? null : seat);
  };

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs">
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
          <span className="text-muted-foreground">
            {isMultiple
              ? t("seats_selected", { defaultValue: "Sélectionnés" })
              : t("seat_selected", { defaultValue: "Votre siège" })}
          </span>
        </div>
      </div>

      <div className="rounded-xl border-2 border-muted-foreground/20 p-3 bg-muted/30 max-w-[280px] mx-auto">
        <div className="flex justify-end mb-3">
          <div className="w-8 h-8 rounded-full border-2 border-muted-foreground/30 flex items-center justify-center">
            <span className="text-[9px] text-muted-foreground font-medium">D</span>
          </div>
        </div>

        <div className="space-y-1.5">
          {Array.from({ length: totalRows }).map((_, rowIdx) => {
            const rowStart = rowIdx * seatsPerRow;
            const leftSeats = allSeats.slice(rowStart, rowStart + leftCols);
            const rightSeats = allSeats.slice(rowStart + leftCols, rowStart + seatsPerRow);

            return (
              <div key={rowIdx} className="flex items-center justify-center gap-3">
                <div className="flex gap-1">
                  {leftSeats.map((seat) => (
                    <SeatButton
                      key={seat}
                      seat={seat}
                      isOccupied={occupiedSet.has(seat)}
                      isSelected={selectedSet.has(seat)}
                      atSelectionLimit={
                        isMultiple &&
                        !selectedSet.has(seat) &&
                        selectedSeats.length >= (maxSelections ?? 0)
                      }
                      onClick={() => handleSeatClick(seat)}
                    />
                  ))}
                  {leftSeats.length < leftCols &&
                    Array.from({ length: leftCols - leftSeats.length }).map((_, i) => (
                      <div key={`empty-l-${i}`} className="w-9 h-9" />
                    ))}
                </div>

                <div className="w-4" />

                <div className="flex gap-1">
                  {rightSeats.map((seat) => (
                    <SeatButton
                      key={seat}
                      seat={seat}
                      isOccupied={occupiedSet.has(seat)}
                      isSelected={selectedSet.has(seat)}
                      atSelectionLimit={
                        isMultiple &&
                        !selectedSet.has(seat) &&
                        selectedSeats.length >= (maxSelections ?? 0)
                      }
                      onClick={() => handleSeatClick(seat)}
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

      {isMultiple ? (
        selectedSeats.length > 0 ? (
          <p className="text-center text-sm font-medium text-primary">
            {t("seats_label", { defaultValue: "Sièges" })} :{" "}
            {selectedSeats.join(", ")}
            {maxSelections ? ` (${selectedSeats.length}/${maxSelections})` : null}
          </p>
        ) : maxSelections ? (
          <p className="text-center text-xs text-muted-foreground">
            {t("seats_pick_hint", {
              defaultValue: "Sélectionnez {{count}} siège(s)",
              count: maxSelections,
            })}
          </p>
        ) : null
      ) : selectedSeat ? (
        <p className="text-center text-sm font-medium text-primary">
          {t("seat_label", { defaultValue: "Siège" })} #{selectedSeat}
        </p>
      ) : null}
    </div>
  );
}

function SeatButton({
  seat,
  isOccupied,
  isSelected,
  atSelectionLimit,
  onClick,
}: {
  seat: string;
  isOccupied: boolean;
  isSelected: boolean;
  atSelectionLimit: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      disabled={isOccupied || atSelectionLimit}
      onClick={onClick}
      className={cn(
        "w-9 h-9 rounded-md text-[10px] font-bold transition-all flex items-center justify-center",
        isOccupied
          ? "bg-destructive/15 border-2 border-destructive/30 text-destructive/60 cursor-not-allowed"
          : atSelectionLimit
            ? "bg-muted border-2 border-muted-foreground/10 text-muted-foreground/40 cursor-not-allowed"
          : isSelected
            ? "bg-primary border-2 border-primary text-primary-foreground scale-105 shadow-md cursor-pointer"
            : "bg-background border-2 border-muted-foreground/20 text-foreground hover:border-primary/60 hover:bg-primary/5 cursor-pointer",
      )}
    >
      {seat}
    </button>
  );
}
