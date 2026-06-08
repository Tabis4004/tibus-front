import { useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import { MessageCircleIcon, PhoneIcon, MailIcon, UserIcon, BuildingIcon } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Textarea } from "@/components/ui/textarea.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Label } from "@/components/ui/label.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import {
  buildMailtoUrl,
  buildWhatsappUrl,
  getContactOptionsSupabase,
  getContactTarget,
  listCompaniesForContactSupabase,
  type ContactOptions,
} from "@/lib/supabase/contact.ts";

type CompanyOption = { _id: string; name: string };

export default function SupabaseContactPage() {
  const { t } = useTranslation("common");

  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [inquiryTo, setInquiryTo] = useState("platform");
  const [message, setMessage] = useState("");
  const [companies, setCompanies] = useState<CompanyOption[]>([]);
  const [contactOptions, setContactOptions] = useState<ContactOptions | null>(null);

  useEffect(() => {
    void listCompaniesForContactSupabase()
      .then(setCompanies)
      .catch(() => setCompanies([]));
    void getContactOptionsSupabase()
      .then(setContactOptions)
      .catch(() =>
        setContactOptions({ platformWhatsapp: null, platformNotificationEmail: null, companies: [] }),
      );
  }, []);

  const target = useMemo(
    () => getContactTarget(contactOptions, inquiryTo),
    [contactOptions, inquiryTo],
  );

  const outboundMessage = useMemo(() => {
    const lines = [
      t("contact.whatsapp_greeting", {
        defaultValue: "Hello! I'm contacting you from Tibus.",
      }),
    ];
    if (name.trim()) lines.push(`${t("contact.name", { defaultValue: "Name" })}: ${name.trim()}`);
    if (email.trim()) lines.push(`${t("contact.email", { defaultValue: "Email" })}: ${email.trim()}`);
    if (phone.trim()) lines.push(`${t("contact.phone", { defaultValue: "Phone" })}: ${phone.trim()}`);
    if (message.trim()) lines.push("", message.trim());
    return lines.join("\n");
  }, [t, name, email, phone, message]);

  const whatsappUrl = target.whatsappNumber
    ? buildWhatsappUrl(target.whatsappNumber, outboundMessage)
    : null;

  const mailtoUrl = target.notificationEmail
    ? buildMailtoUrl(
        target.notificationEmail,
        t("contact.email_subject", { defaultValue: "Tibus — Contact request" }),
        outboundMessage,
      )
    : null;

  const hasChannel = Boolean(whatsappUrl || mailtoUrl);

  return (
    <div className="max-w-lg mx-auto px-4 py-10 space-y-6">
      <div className="text-center space-y-2">
        <div className="w-14 h-14 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto">
          <MessageCircleIcon className="w-7 h-7 text-primary" />
        </div>
        <h1 className="text-2xl font-extrabold tracking-tight">
          {t("contact.title", { defaultValue: "Contact Us" })}
        </h1>
        <p className="text-sm text-muted-foreground">
          {t("contact.subtitle_direct", {
            defaultValue: "Reach us directly on WhatsApp or by email",
          })}
        </p>
      </div>

      <Card>
        <CardHeader className="pb-4">
          <CardTitle className="text-base">
            {t("contact.form_title", { defaultValue: "Your message" })}
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-1.5">
            <Label className="flex items-center gap-1.5">
              <BuildingIcon className="w-3.5 h-3.5" />
              {t("contact.inquiry_to", { defaultValue: "Contact" })} *
            </Label>
            <Select value={inquiryTo} onValueChange={setInquiryTo}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="platform">
                  {t("contact.platform_tibus", { defaultValue: "Platform Tibus" })}
                </SelectItem>
                {companies.map((c) => (
                  <SelectItem key={c._id} value={c._id}>
                    {c.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-1.5">
            <Label className="flex items-center gap-1.5">
              <UserIcon className="w-3.5 h-3.5" />
              {t("contact.name", { defaultValue: "Name" })}
            </Label>
            <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="John Smith" />
          </div>

          <div className="space-y-1.5">
            <Label className="flex items-center gap-1.5">
              <MailIcon className="w-3.5 h-3.5" />
              {t("contact.email", { defaultValue: "Email" })}
            </Label>
            <Input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="example@gmail.com"
            />
          </div>

          <div className="space-y-1.5">
            <Label className="flex items-center gap-1.5">
              <PhoneIcon className="w-3.5 h-3.5" />
              {t("contact.phone", { defaultValue: "Phone" })}
            </Label>
            <Input
              type="tel"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              placeholder="+237 6XX XXX XXX"
            />
          </div>

          <div className="space-y-1.5">
            <Label>{t("contact.message", { defaultValue: "Message" })}</Label>
            <Textarea
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              placeholder={t("contact.message_placeholder", { defaultValue: "Describe your inquiry..." })}
              rows={4}
            />
          </div>
        </CardContent>
      </Card>

      {hasChannel ? (
        <div className="space-y-3">
          {whatsappUrl ? (
            <a href={whatsappUrl} target="_blank" rel="noopener noreferrer" className="block">
              <Button
                size="lg"
                className="w-full h-14 cursor-pointer gap-3 bg-[#25D366] hover:bg-[#20BD5A] text-white"
              >
                <svg viewBox="0 0 24 24" className="w-6 h-6 fill-current" aria-hidden="true">
                  <path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413z" />
                </svg>
                {t("contact.whatsapp_chat", { defaultValue: "Chat on WhatsApp" })}
              </Button>
            </a>
          ) : null}

          {mailtoUrl ? (
            <a href={mailtoUrl} className="block">
              <Button size="lg" variant="outline" className="w-full h-14 cursor-pointer gap-3">
                <MailIcon className="w-5 h-5" />
                {t("contact.send_email", { defaultValue: "Send by email" })}
              </Button>
            </a>
          ) : null}
        </div>
      ) : (
        <div className="rounded-xl border border-dashed p-4 text-center">
          <p className="text-sm text-muted-foreground">
            {t("contact.no_channel", {
              defaultValue: "No contact channel configured for this recipient yet",
            })}
          </p>
        </div>
      )}
    </div>
  );
}
