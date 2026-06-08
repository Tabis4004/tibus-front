import { useEffect, useMemo, useState } from "react";
import { useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { CopyIcon, GiftIcon, Share2Icon } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  getMyReferralProfileSupabase,
  recordReferralShareSupabase,
  type ReferralProfile,
} from "@/lib/supabase/platform-loyalty.ts";

export default function ReferralPage() {
  const { t } = useTranslation("traveler");
  const { lng } = useParams<{ lng: string }>();
  const [profile, setProfile] = useState<ReferralProfile | null>(null);
  const [sharing, setSharing] = useState(false);

  useEffect(() => {
    void getMyReferralProfileSupabase()
      .then(setProfile)
      .catch(() => setProfile({ authenticated: false }));
  }, []);

  const referralLink = useMemo(() => {
    if (!profile?.referralCode) return "";
    const origin = typeof window !== "undefined" ? window.location.origin : "";
    return `${origin}/${lng ?? "fr"}?ref=${profile.referralCode}`;
  }, [lng, profile?.referralCode]);

  const copyLink = async () => {
    if (!referralLink) return;
    try {
      await navigator.clipboard.writeText(referralLink);
      toast.success(t("referral.copied", { defaultValue: "Lien copié" }));
    } catch {
      toast.error(t("errors.generic", { ns: "common" }));
    }
  };

  const shareLink = async () => {
    if (!referralLink) return;
    setSharing(true);
    try {
      if (navigator.share) {
        await navigator.share({
          title: "Tibus",
          text: t("referral.share_text", { defaultValue: "Rejoins Tibus avec mon lien parrain" }),
          url: referralLink,
        });
      } else {
        await copyLink();
      }
      const result = await recordReferralShareSupabase();
      if (result.success) {
        toast.success(
          t("referral.share_reward", {
            defaultValue: "+{{points}} points plateforme",
            points: result.points ?? 0,
          }),
        );
        const refreshed = await getMyReferralProfileSupabase();
        setProfile(refreshed);
      } else if (result.error) {
        toast.message(result.error);
      }
    } catch {
      // user cancelled native share
    } finally {
      setSharing(false);
    }
  };

  if (!profile) {
    return <Skeleton className="h-64 w-full max-w-lg mx-auto" />;
  }

  if (!profile.authenticated) {
    return (
      <p className="text-sm text-muted-foreground text-center py-16">
        {t("referral.login_required", { defaultValue: "Connectez-vous pour accéder au parrainage." })}
      </p>
    );
  }

  return (
    <div className="max-w-lg mx-auto px-4 py-8 space-y-4">
      <div className="text-center space-y-2">
        <GiftIcon className="w-10 h-10 text-primary mx-auto" />
        <h1 className="text-xl font-extrabold">{t("referral.title", { defaultValue: "Parrainage Tibus" })}</h1>
        <p className="text-sm text-muted-foreground">
          {t("referral.desc", {
            defaultValue: "Invitez des amis et gagnez des points plateforme utilisables sur vos billets.",
          })}
        </p>
      </div>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base">{t("referral.balance", { defaultValue: "Vos points plateforme" })}</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-3xl font-extrabold text-primary">{profile.platformPoints ?? 0}</p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base">{t("referral.code_label", { defaultValue: "Votre code parrain" })}</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <p className="font-mono text-2xl tracking-widest text-center">{profile.referralCode}</p>
          <p className="text-xs text-muted-foreground break-all text-center">{referralLink}</p>
          <div className="flex gap-2">
            <Button variant="outline" className="flex-1 cursor-pointer gap-2" onClick={() => void copyLink()}>
              <CopyIcon className="w-4 h-4" />
              {t("referral.copy", { defaultValue: "Copier" })}
            </Button>
            <Button className="flex-1 cursor-pointer gap-2" disabled={sharing} onClick={() => void shareLink()}>
              <Share2Icon className="w-4 h-4" />
              {t("referral.share", { defaultValue: "Partager" })}
            </Button>
          </div>
          {profile.platformActive ? (
            <p className="text-xs text-muted-foreground text-center">
              {t("referral.share_hint", {
                defaultValue: "Chaque partage peut rapporter jusqu'à {{limit}} fois par jour (+{{points}} pts).",
                limit: profile.referralShareDailyLimit ?? 1,
                points: profile.referralSharePoints ?? 0,
              })}
            </p>
          ) : null}
        </CardContent>
      </Card>
    </div>
  );
}
