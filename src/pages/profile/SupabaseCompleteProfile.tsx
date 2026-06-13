import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { UserCircle } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  CardDescription,
} from "@/components/ui/card.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Spinner } from "@/components/ui/spinner.tsx";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { useAppUser, refreshAppUserAsync } from "@/hooks/use-app-user";
import { completeUserProfile } from "@/lib/auth/complete-profile";
import { hasCompletedProfileOnce } from "@/lib/auth/profile-completion";
import { listCountriesSupabase, type CountryRow } from "@/lib/supabase/geography";

const profileSchema = z.object({
  fullName: z.string().min(2, "Full name is required"),
  username: z.string().min(3).regex(/^[a-zA-Z0-9_]+$/, "Invalid username"),
  phone: z.string().min(6, "Phone number is required"),
  email: z.string().email("Invalid email").or(z.literal("")).optional(),
  countryId: z.string().min(1, "Country is required"),
});

type ProfileFormData = z.infer<typeof profileSchema>;

export default function SupabaseCompleteProfile() {
  const { t } = useTranslation("common");
  const navigate = useNavigate();
  const { appUserId, session } = useSupabaseAuth();
  const { profile, isReady } = useAppUser();
  const [countries, setCountries] = useState<CountryRow[] | undefined>(undefined);
  const [isSubmitting, setIsSubmitting] = useState(false);

  useEffect(() => {
    if (isReady && hasCompletedProfileOnce(profile)) {
      navigate("/", { replace: true });
    }
  }, [isReady, profile, navigate]);

  useEffect(() => {
    void listCountriesSupabase()
      .then(setCountries)
      .catch(() => setCountries([]));
  }, []);

  const {
    register,
    handleSubmit,
    setValue,
    watch,
    formState: { errors },
  } = useForm<ProfileFormData>({
    resolver: zodResolver(profileSchema),
    defaultValues: {
      fullName: profile ? `${profile.firstName} ${profile.lastName}`.trim() : "",
      username: profile?.username ?? "",
      phone: profile?.phone ?? "",
      email: profile?.email ?? session?.user.email ?? "",
      countryId: profile?.countryId ?? "",
    },
  });

  useEffect(() => {
    if (!profile) return;
    setValue("fullName", `${profile.firstName} ${profile.lastName}`.trim());
    setValue("username", profile.username);
    setValue("phone", profile.phone ?? "");
    setValue("email", profile.email ?? session?.user.email ?? "");
    if (profile.countryId) setValue("countryId", profile.countryId);
  }, [profile, session, setValue]);

  const selectedCountryId = watch("countryId");

  const onSubmit = async (data: ProfileFormData) => {
    if (!appUserId) return;
    setIsSubmitting(true);
    try {
      await completeUserProfile({
        userId: appUserId,
        fullName: data.fullName,
        username: data.username,
        phone: data.phone,
        email: data.email || undefined,
        countryId: data.countryId,
      });
      await refreshAppUserAsync();
      toast.success(t("profile.completed_success"));
      navigate("/", { replace: true });
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("errors.generic"));
    } finally {
      setIsSubmitting(false);
    }
  };

  if (!countries) {
    return (
      <div className="flex flex-col items-center justify-center min-h-screen p-6">
        <Skeleton className="h-96 w-full max-w-md" />
      </div>
    );
  }

  return (
    <div className="flex flex-col items-center justify-center min-h-screen p-4 bg-background">
      <Card className="w-full max-w-md">
        <CardHeader className="text-center">
          <div className="mx-auto mb-2 w-16 h-16 rounded-full bg-primary/10 flex items-center justify-center">
            <UserCircle className="w-8 h-8 text-primary" />
          </div>
          <CardTitle className="text-xl">{t("profile.complete_title")}</CardTitle>
          <CardDescription>{t("profile.complete_desc")}</CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="fullName">{t("profile.full_name")} *</Label>
              <Input id="fullName" {...register("fullName")} />
              {errors.fullName && (
                <p className="text-sm text-destructive">{errors.fullName.message}</p>
              )}
            </div>
            <div className="space-y-2">
              <Label htmlFor="username">{t("profile.username")} *</Label>
              <Input id="username" {...register("username")} />
              {errors.username && (
                <p className="text-sm text-destructive">{errors.username.message}</p>
              )}
            </div>
            <div className="space-y-2">
              <Label htmlFor="phone">{t("labels.phone")} *</Label>
              <Input id="phone" type="tel" {...register("phone")} />
              {errors.phone && (
                <p className="text-sm text-destructive">{errors.phone.message}</p>
              )}
            </div>
            <div className="space-y-2">
              <Label htmlFor="email">{t("profile.email_optional")}</Label>
              <Input id="email" type="email" {...register("email")} />
            </div>
            <div className="space-y-2">
              <Label>{t("labels.country")} *</Label>
              <Select
                value={selectedCountryId}
                onValueChange={(val) => setValue("countryId", val, { shouldValidate: true })}
              >
                <SelectTrigger>
                  <SelectValue placeholder={t("profile.select_country")} />
                </SelectTrigger>
                <SelectContent>
                  {countries.map((c) => (
                    <SelectItem key={c._id} value={c._id}>
                      {c.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {errors.countryId && (
                <p className="text-sm text-destructive">{errors.countryId.message}</p>
              )}
            </div>
            <Button type="submit" className="w-full" disabled={isSubmitting}>
              {isSubmitting ? <Spinner className="mr-2" /> : null}
              {isSubmitting ? t("buttons.saving") : t("profile.complete_btn")}
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  );
}
