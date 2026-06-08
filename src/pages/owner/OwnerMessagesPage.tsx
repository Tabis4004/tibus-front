import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { MailIcon, PhoneIcon } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  getOwnerContactSettingsSupabase,
  setContactSettingsSupabase,
  type OwnerContactSettings,
} from "@/lib/supabase/contact.ts";

export default function OwnerMessagesPage() {
  const { t } = useTranslation("owner");
  const { t: tc } = useTranslation("common");
  const [settings, setSettings] = useState<OwnerContactSettings | null>(null);
  const [whatsappNumber, setWhatsappNumber] = useState("");
  const [notificationEmail, setNotificationEmail] = useState("");
  const [savingSettings, setSavingSettings] = useState(false);

  const loadSettings = () => {
    setSettings(null);
    void getOwnerContactSettingsSupabase()
      .then((row) => {
        setSettings(row);
        setWhatsappNumber(row.whatsappNumber ?? "");
        setNotificationEmail(row.notificationEmail ?? "");
      })
      .catch((err) => {
        toast.error(err instanceof Error ? err.message : t("messages.settings_load_error"));
        setSettings({ scope: null, whatsappNumber: null, notificationEmail: null });
      });
  };

  useEffect(() => {
    loadSettings();
  }, []);

  const handleSaveSettings = async () => {
    if (!settings?.scope) {
      toast.error(t("messages.settings_no_company"));
      return;
    }
    if (!whatsappNumber.trim() && !notificationEmail.trim()) {
      toast.error(t("messages.settings_required"));
      return;
    }
    setSavingSettings(true);
    try {
      await setContactSettingsSupabase(settings.scope, {
        whatsappNumber: whatsappNumber.trim(),
        notificationEmail: notificationEmail.trim(),
      });
      toast.success(t("messages.settings_saved"));
      loadSettings();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("messages.settings_save_error"));
    } finally {
      setSavingSettings(false);
    }
  };

  return (
    <div className="p-4 md:p-6 max-w-2xl mx-auto space-y-4">
      <div>
        <h1 className="text-xl font-extrabold">{t("messages.title")}</h1>
        <p className="text-sm text-muted-foreground mt-1">{t("messages.desc")}</p>
      </div>

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base">{t("messages.settings_title")}</CardTitle>
          <p className="text-xs text-muted-foreground">{t("messages.settings_desc")}</p>
        </CardHeader>
        <CardContent className="space-y-4">
          {settings === null ? (
            <Skeleton className="h-24 w-full" />
          ) : (
            <>
              <div className="space-y-1.5">
                <Label className="flex items-center gap-1.5">
                  <PhoneIcon className="w-3.5 h-3.5" />
                  {t("messages.whatsapp_label")}
                </Label>
                <Input
                  value={whatsappNumber}
                  onChange={(e) => setWhatsappNumber(e.target.value)}
                  placeholder="+225 07 XX XX XX XX"
                />
              </div>
              <div className="space-y-1.5">
                <Label className="flex items-center gap-1.5">
                  <MailIcon className="w-3.5 h-3.5" />
                  {t("messages.email_label")}
                </Label>
                <Input
                  type="email"
                  value={notificationEmail}
                  onChange={(e) => setNotificationEmail(e.target.value)}
                  placeholder="contact@macompagnie.com"
                />
              </div>
              <Button
                className="cursor-pointer"
                disabled={savingSettings || !settings.scope}
                onClick={() => void handleSaveSettings()}
              >
                {savingSettings ? t("messages.settings_saving") : tc("buttons.save")}
              </Button>
            </>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
