import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { MessageSquareIcon, PlusIcon, TrashIcon } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Textarea } from "@/components/ui/textarea.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { PAYMENT_NETWORK_OPTIONS } from "@/lib/payment-networks.ts";
import {
  getTravelerPaymentNoticeSupabase,
  upsertTravelerPaymentNoticeSupabase,
  type TravelerPaymentNotice,
  type TravelerPaymentNoticeHint,
} from "@/lib/supabase/traveler-payment-notice.ts";

type CountryOption = { id: string; name: string };

function emptyHint(sortOrder: number): TravelerPaymentNoticeHint {
  return {
    countryId: "",
    countryCode: "",
    cheapestNetwork: "wave",
    sortOrder,
    isActive: true,
  };
}

export default function TravelerBookingNoticePanel({
  countries,
}: {
  countries: CountryOption[];
}) {
  const { t } = useTranslation("admin");
  const { t: tc } = useTranslation("common");
  const [notice, setNotice] = useState<TravelerPaymentNotice | null>(null);
  const [saving, setSaving] = useState(false);

  const load = () => {
    setNotice(null);
    void getTravelerPaymentNoticeSupabase()
      .then(setNotice)
      .catch((err) => {
        toast.error(err instanceof Error ? err.message : t("booking_notice.load_error"));
      });
  };

  useEffect(() => {
    load();
  }, []);

  const updateHint = (index: number, patch: Partial<TravelerPaymentNoticeHint>) => {
    setNotice((current) => {
      if (!current) return current;
      const hints = [...current.hints];
      hints[index] = { ...hints[index], ...patch };
      return { ...current, hints };
    });
  };

  const addHint = () => {
    setNotice((current) => {
      if (!current) return current;
      const nextOrder = current.hints.length + 1;
      return { ...current, hints: [...current.hints, emptyHint(nextOrder)] };
    });
  };

  const removeHint = (index: number) => {
    setNotice((current) => {
      if (!current) return current;
      return { ...current, hints: current.hints.filter((_, i) => i !== index) };
    });
  };

  const handleSave = async () => {
    if (!notice) return;
    setSaving(true);
    try {
      const saved = await upsertTravelerPaymentNoticeSupabase(notice);
      setNotice(saved);
      toast.success(t("booking_notice.saved"));
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("booking_notice.save_error"));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Card className="border-dashed">
      <CardHeader className="pb-3">
        <CardTitle className="text-base flex items-center gap-2">
          <MessageSquareIcon className="w-4 h-4" />
          {t("booking_notice.title")}
        </CardTitle>
        <p className="text-sm text-muted-foreground">{t("booking_notice.desc")}</p>
      </CardHeader>
      <CardContent className="space-y-4">
        {notice === null ? (
          <Skeleton className="h-48 w-full" />
        ) : (
          <>
            <div className="space-y-1.5">
              <Label>{t("booking_notice.field_title")}</Label>
              <Input
                value={notice.title}
                onChange={(e) => setNotice({ ...notice, title: e.target.value })}
              />
            </div>
            <div className="space-y-1.5">
              <Label>{t("booking_notice.field_p1")}</Label>
              <Textarea
                rows={3}
                value={notice.paragraph1}
                onChange={(e) => setNotice({ ...notice, paragraph1: e.target.value })}
              />
            </div>
            <div className="space-y-1.5">
              <Label>{t("booking_notice.field_p2")}</Label>
              <Textarea
                rows={3}
                value={notice.paragraph2}
                onChange={(e) => setNotice({ ...notice, paragraph2: e.target.value })}
              />
            </div>
            <div className="space-y-1.5">
              <Label>{t("booking_notice.field_network_intro")}</Label>
              <Textarea
                rows={2}
                value={notice.networkIntro}
                onChange={(e) => setNotice({ ...notice, networkIntro: e.target.value })}
              />
            </div>

            <div className="space-y-2">
              <div className="flex items-center justify-between gap-2">
                <Label>{t("booking_notice.hints_title")}</Label>
                <Button type="button" size="sm" variant="secondary" onClick={addHint} className="gap-1.5">
                  <PlusIcon className="w-4 h-4" />
                  {t("booking_notice.add_hint")}
                </Button>
              </div>
              {notice.hints.length === 0 ? (
                <p className="text-sm text-muted-foreground">{t("booking_notice.hints_empty")}</p>
              ) : (
                <div className="space-y-3">
                  {notice.hints.map((hint, index) => (
                    <div key={`${hint.countryId}-${index}`} className="grid gap-2 rounded-lg border p-3 md:grid-cols-5">
                      <div className="space-y-1 md:col-span-2">
                        <Label className="text-xs">{t("booking_notice.hint_country")}</Label>
                        <Select
                          value={hint.countryId || undefined}
                          onValueChange={(value) => {
                            const country = countries.find((item) => item.id === value);
                            updateHint(index, {
                              countryId: value,
                              countryCode: hint.countryCode || country?.name.slice(0, 2).toUpperCase() || "",
                            });
                          }}
                        >
                          <SelectTrigger><SelectValue placeholder={t("commissions.select_country")} /></SelectTrigger>
                          <SelectContent>
                            {countries.map((country) => (
                              <SelectItem key={country.id} value={country.id}>{country.name}</SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>
                      <div className="space-y-1">
                        <Label className="text-xs">{t("booking_notice.hint_code")}</Label>
                        <Input
                          value={hint.countryCode}
                          onChange={(e) => updateHint(index, { countryCode: e.target.value.toUpperCase() })}
                          placeholder="CI"
                        />
                      </div>
                      <div className="space-y-1">
                        <Label className="text-xs">{t("booking_notice.hint_network")}</Label>
                        <Select
                          value={hint.cheapestNetwork}
                          onValueChange={(value) => updateHint(index, { cheapestNetwork: value })}
                        >
                          <SelectTrigger><SelectValue /></SelectTrigger>
                          <SelectContent>
                            {PAYMENT_NETWORK_OPTIONS.filter((item) => item.value !== "unknown").map((option) => (
                              <SelectItem key={option.value} value={option.value}>
                                {option.labelFr}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>
                      <div className="flex items-end">
                        <Button
                          type="button"
                          size="icon"
                          variant="outline"
                          onClick={() => removeHint(index)}
                        >
                          <TrashIcon className="w-4 h-4" />
                        </Button>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>

            <Button onClick={handleSave} disabled={saving}>
              {saving ? tc("buttons.saving", { defaultValue: "Enregistrement..." }) : tc("buttons.save")}
            </Button>
          </>
        )}
      </CardContent>
    </Card>
  );
}
