import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { normalizePhoneE164 } from "@/lib/auth/phone";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Spinner } from "@/components/ui/spinner.tsx";
import {
  InputOTP,
  InputOTPGroup,
  InputOTPSlot,
} from "@/components/ui/input-otp.tsx";
import CguAcceptanceCheckbox from "@/components/legal/CguAcceptanceCheckbox.tsx";

type PhoneOtpPanelProps = {
  onSuccess: () => Promise<void>;
};

const OTP_LENGTH = 6;
const RESEND_COOLDOWN_SEC = 60;

export default function PhoneOtpPanel({ onSuccess }: PhoneOtpPanelProps) {
  const { t } = useTranslation("common");
  const { signInWithPhoneOtp, verifyPhoneOtp } = useSupabaseAuth();
  const [phone, setPhone] = useState("");
  const [normalizedPhone, setNormalizedPhone] = useState<string | null>(null);
  const [otp, setOtp] = useState("");
  const [step, setStep] = useState<"phone" | "otp">("phone");
  const [submitting, setSubmitting] = useState(false);
  const [acceptedCgu, setAcceptedCgu] = useState(false);
  const [resendIn, setResendIn] = useState(0);

  useEffect(() => {
    if (resendIn <= 0) return;
    const timer = window.setInterval(() => {
      setResendIn((value) => (value > 0 ? value - 1 : 0));
    }, 1000);
    return () => window.clearInterval(timer);
  }, [resendIn]);

  const sendOtp = async () => {
    if (!acceptedCgu) {
      toast.error(t("auth.cgu_required", { defaultValue: "Veuillez accepter les CGU pour continuer." }));
      return;
    }

    let e164: string;
    try {
      e164 = normalizePhoneE164(phone);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("errors.generic"));
      return;
    }

    setSubmitting(true);
    try {
      await signInWithPhoneOtp(e164);
      setNormalizedPhone(e164);
      setStep("otp");
      setOtp("");
      setResendIn(RESEND_COOLDOWN_SEC);
      toast.success(
        t("auth.otp_sent", {
          defaultValue: "Code envoyé par SMS. Saisissez-le ci-dessous.",
        }),
      );
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("errors.generic"));
    } finally {
      setSubmitting(false);
    }
  };

  const verifyOtp = async () => {
    if (!normalizedPhone) return;
    if (otp.length !== OTP_LENGTH) {
      toast.error(
        t("auth.otp_incomplete", {
          defaultValue: "Saisissez le code à 6 chiffres.",
        }),
      );
      return;
    }

    setSubmitting(true);
    try {
      await verifyPhoneOtp(normalizedPhone, otp);
      toast.success(t("auth.sign_in_success", { defaultValue: "Connexion réussie" }));
      await onSuccess();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("errors.generic"));
    } finally {
      setSubmitting(false);
    }
  };

  if (step === "otp") {
    return (
      <div className="space-y-4 pt-4">
        <p className="text-sm text-muted-foreground">
          {t("auth.otp_sent_to", {
            defaultValue: "Code envoyé au {{phone}}",
            phone: normalizedPhone,
          })}
        </p>
        <div className="space-y-2">
          <Label htmlFor="phone-otp">
            {t("auth.otp_code", { defaultValue: "Code de confirmation" })}
          </Label>
          <InputOTP
            id="phone-otp"
            maxLength={OTP_LENGTH}
            value={otp}
            onChange={setOtp}
            containerClassName="justify-center"
          >
            <InputOTPGroup>
              {Array.from({ length: OTP_LENGTH }, (_, index) => (
                <InputOTPSlot key={index} index={index} />
              ))}
            </InputOTPGroup>
          </InputOTP>
        </div>
        <Button
          type="button"
          className="w-full"
          disabled={submitting || otp.length !== OTP_LENGTH}
          onClick={() => void verifyOtp()}
        >
          {submitting ? <Spinner className="size-4" /> : t("auth.confirm_otp", { defaultValue: "Confirmer" })}
        </Button>
        <div className="flex items-center justify-between gap-2 text-sm">
          <Button
            type="button"
            variant="ghost"
            size="sm"
            onClick={() => {
              setStep("phone");
              setOtp("");
            }}
          >
            {t("actions.change_phone", { defaultValue: "Changer de numéro" })}
          </Button>
          <Button
            type="button"
            variant="link"
            size="sm"
            disabled={submitting || resendIn > 0}
            onClick={() => void sendOtp()}
          >
            {resendIn > 0
              ? t("auth.resend_otp_in", {
                  defaultValue: "Renvoyer dans {{seconds}} s",
                  seconds: resendIn,
                })
              : t("auth.resend_otp", { defaultValue: "Renvoyer le code" })}
          </Button>
        </div>
      </div>
    );
  }

  return (
    <form
      className="space-y-4 pt-4"
      onSubmit={(e) => {
        e.preventDefault();
        void sendOtp();
      }}
    >
      <p className="text-sm text-muted-foreground">
        {t("auth.phone_otp_hint", {
          defaultValue: "Connexion ou inscription par SMS (code à 6 chiffres).",
        })}
      </p>
      <div className="space-y-2">
        <Label htmlFor="phone-login">
          {t("labels.phone", { defaultValue: "Téléphone" })}
        </Label>
        <Input
          id="phone-login"
          type="tel"
          autoComplete="tel"
          value={phone}
          onChange={(e) => setPhone(e.target.value)}
          placeholder="+225 07 00 00 00 00"
          required
        />
      </div>
      <CguAcceptanceCheckbox
        id="phone-cgu"
        checked={acceptedCgu}
        onCheckedChange={setAcceptedCgu}
      />
      <Button type="submit" className="w-full" disabled={submitting || !acceptedCgu}>
        {submitting ? (
          <Spinner className="size-4" />
        ) : (
          t("auth.send_otp", { defaultValue: "Recevoir le code" })
        )}
      </Button>
    </form>
  );
}
