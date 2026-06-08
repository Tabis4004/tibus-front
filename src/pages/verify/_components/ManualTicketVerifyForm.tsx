import { useState, type FormEvent } from "react";
import { normalizeTicketReference } from "@/lib/ticket-verify-url.ts";
import { KeyboardIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";

export default function ManualTicketVerifyForm({
  onSubmit,
  disabled = false,
}: {
  onSubmit: (reference: string) => void;
  disabled?: boolean;
}) {
  const [reference, setReference] = useState("");

  const handleSubmit = (event: FormEvent) => {
    event.preventDefault();
    const normalized = normalizeTicketReference(reference);
    if (!normalized) return;
    onSubmit(normalized);
  };

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base flex items-center gap-2">
          <KeyboardIcon className="w-4 h-4" />
          Vérification manuelle
        </CardTitle>
      </CardHeader>
      <CardContent>
        <form onSubmit={handleSubmit} className="space-y-3">
          <div className="space-y-1.5">
            <Label htmlFor="ticket-reference">Numéro du billet</Label>
            <Input
              id="ticket-reference"
              value={reference}
              onChange={(event) => setReference(event.target.value.toUpperCase())}
              placeholder="TB-XXXXXXXX"
              autoCapitalize="characters"
              autoComplete="off"
              spellCheck={false}
              disabled={disabled}
            />
            <p className="text-[11px] text-muted-foreground">
              Saisissez la référence imprimée sur le billet si le QR code est illisible.
            </p>
          </div>
          <Button type="submit" className="w-full cursor-pointer" disabled={disabled || !reference.trim()}>
            Vérifier le billet
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}
