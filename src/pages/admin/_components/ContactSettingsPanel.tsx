import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { BuildingIcon, MessageCircleIcon } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Input } from "@/components/ui/input.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import {
  getContactOptionsSupabase,
  setContactSettingsSupabase,
  type ContactOptions,
} from "@/lib/supabase/contact.ts";

type CompanyOption = { id: string; name: string };

export default function ContactSettingsPanel({
  companies,
}: {
  companies: CompanyOption[];
}) {
  const { t } = useTranslation("admin");
  const { t: tc } = useTranslation("common");

  const [contactOptions, setContactOptions] = useState<ContactOptions | null>(null);
  const [platformNumber, setPlatformNumber] = useState("");
  const [platformEmail, setPlatformEmail] = useState("");
  const [companyId, setCompanyId] = useState("");
  const [companyNumber, setCompanyNumber] = useState("");
  const [companyEmail, setCompanyEmail] = useState("");
  const [loading, setLoading] = useState(false);

  const load = () => {
    setContactOptions(null);
    void getContactOptionsSupabase()
      .then(setContactOptions)
      .catch((err) => {
        toast.error(err instanceof Error ? err.message : t("contact_settings.save_error"));
      });
  };

  useEffect(() => {
    load();
  }, []);

  const currentPlatform = contactOptions?.platformWhatsapp ?? "";
  const currentPlatformEmail = contactOptions?.platformNotificationEmail ?? "";

  const handleSavePlatform = async () => {
    const whatsapp = (platformNumber || currentPlatform).trim();
    const email = (platformEmail || currentPlatformEmail).trim();
    if (!whatsapp && !email) return;
    setLoading(true);
    try {
      await setContactSettingsSupabase("platform", {
        whatsappNumber: whatsapp,
        notificationEmail: email,
      });
      toast.success(t("contact_settings.saved", { defaultValue: "Contact settings saved" }));
      setPlatformNumber("");
      setPlatformEmail("");
      load();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("contact_settings.save_error"));
    } finally {
      setLoading(false);
    }
  };

  const handleSaveCompany = async () => {
    if (!companyId) return;
    if (!companyNumber.trim() && !companyEmail.trim()) return;
    setLoading(true);
    try {
      await setContactSettingsSupabase(companyId, {
        whatsappNumber: companyNumber.trim(),
        notificationEmail: companyEmail.trim(),
      });
      toast.success(t("contact_settings.saved", { defaultValue: "Contact settings saved" }));
      setCompanyId("");
      setCompanyNumber("");
      setCompanyEmail("");
      load();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("contact_settings.save_error"));
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base flex items-center gap-2">
            <MessageCircleIcon className="w-4 h-4" />
            {t("contact_settings.platform_title", { defaultValue: "Platform contact" })}
          </CardTitle>
          <p className="text-xs text-muted-foreground mt-1">
            {t("contact_settings.platform_desc", {
              defaultValue: "WhatsApp and email shown on the Tibus contact page",
            })}
          </p>
        </CardHeader>
        <CardContent className="space-y-3">
          <Input
            value={platformNumber || currentPlatform}
            onChange={(e) => setPlatformNumber(e.target.value)}
            placeholder={t("contact_settings.whatsapp_placeholder", { defaultValue: "WhatsApp +237…" })}
          />
          <Input
            type="email"
            value={platformEmail || currentPlatformEmail}
            onChange={(e) => setPlatformEmail(e.target.value)}
            placeholder={t("contact_settings.email_placeholder", { defaultValue: "Contact email" })}
          />
          <Button size="sm" className="cursor-pointer" disabled={loading} onClick={() => void handleSavePlatform()}>
            {tc("buttons.save")}
          </Button>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base flex items-center gap-2">
            <BuildingIcon className="w-4 h-4" />
            {t("contact_settings.company_title", { defaultValue: "Company contact" })}
          </CardTitle>
          <p className="text-xs text-muted-foreground mt-1">
            {t("contact_settings.company_desc", {
              defaultValue: "WhatsApp and email for each company on the contact page",
            })}
          </p>
        </CardHeader>
        <CardContent className="space-y-3">
          {contactOptions?.companies && contactOptions.companies.length > 0 ? (
            <div className="space-y-2 mb-4">
              {contactOptions.companies.map((c) => (
                <div key={c.companyId} className="flex items-center gap-3 p-3 rounded-xl bg-muted/50">
                  <BuildingIcon className="w-4 h-4 text-primary shrink-0" />
                  <div className="flex-1 min-w-0">
                    <div className="font-medium text-sm">{c.companyName}</div>
                    <div className="text-xs text-muted-foreground">
                      {c.whatsappNumber ?? "—"}
                      {c.notificationEmail ? ` · ${c.notificationEmail}` : ""}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          ) : null}

          <div className="space-y-2">
            <Select value={companyId} onValueChange={setCompanyId}>
              <SelectTrigger>
                <SelectValue placeholder={t("contact_settings.select_company", { defaultValue: "Select company" })} />
              </SelectTrigger>
              <SelectContent>
                {companies.map((c) => (
                  <SelectItem key={c.id} value={c.id}>
                    {c.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Input
              value={companyNumber}
              onChange={(e) => setCompanyNumber(e.target.value)}
              placeholder={t("contact_settings.whatsapp_placeholder", { defaultValue: "WhatsApp +237…" })}
            />
            <Input
              type="email"
              value={companyEmail}
              onChange={(e) => setCompanyEmail(e.target.value)}
              placeholder={t("contact_settings.email_placeholder", { defaultValue: "Contact email" })}
            />
            <Button
              size="sm"
              className="cursor-pointer"
              disabled={loading || !companyId || (!companyNumber.trim() && !companyEmail.trim())}
              onClick={() => void handleSaveCompany()}
            >
              {tc("buttons.save")}
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
