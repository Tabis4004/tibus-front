import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useMutation, useQuery } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import { ConvexError } from "convex/values";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { UserCircle } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card.tsx";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Spinner } from "@/components/ui/spinner.tsx";
import type { Id } from "@/convex/_generated/dataModel.d.ts";

const profileSchema = z.object({
  fullName: z.string().min(2, "Full name is required"),
  username: z.string().min(3, "Username must be at least 3 characters").regex(/^[a-zA-Z0-9_]+$/, "Only letters, numbers, and underscores"),
  phone: z.string().min(6, "Phone number is required"),
  email: z.string().email("Invalid email").or(z.literal("")).optional(),
  countryId: z.string().min(1, "Country is required"),
});

type ProfileFormData = z.infer<typeof profileSchema>;

export default function CompleteProfile() {
  const { t } = useTranslation("common");
  const navigate = useNavigate();
  const completeProfile = useMutation(api.users.completeProfile);
  const countries = useQuery(api.geography.listCountries);
  const currentUser = useQuery(api.users.getCurrentUser);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const {
    register,
    handleSubmit,
    setValue,
    watch,
    formState: { errors },
  } = useForm<ProfileFormData>({
    resolver: zodResolver(profileSchema),
    defaultValues: {
      fullName: currentUser?.name ?? "",
      username: "",
      phone: "",
      email: currentUser?.email ?? "",
      countryId: "",
    },
  });

  const selectedCountryId = watch("countryId");

  const onSubmit = async (data: ProfileFormData) => {
    setIsSubmitting(true);
    try {
      await completeProfile({
        fullName: data.fullName,
        username: data.username,
        phone: data.phone,
        email: data.email || undefined,
        countryId: data.countryId as Id<"countries">,
      });
      toast.success(t("profile.completed_success"));
      navigate("/", { replace: true });
    } catch (error) {
      if (error instanceof ConvexError) {
        const { message } = error.data as { code: string; message: string };
        toast.error(message);
      } else {
        toast.error(t("errors.generic"));
      }
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
            {/* Full Name */}
            <div className="space-y-2">
              <Label htmlFor="fullName">{t("profile.full_name")} *</Label>
              <Input
                id="fullName"
                placeholder="John Smith"
                {...register("fullName")}
              />
              {errors.fullName && (
                <p className="text-sm text-destructive">{errors.fullName.message}</p>
              )}
            </div>

            {/* Username */}
            <div className="space-y-2">
              <Label htmlFor="username">{t("profile.username")} *</Label>
              <Input
                id="username"
                placeholder="johnsmith"
                {...register("username")}
              />
              {errors.username && (
                <p className="text-sm text-destructive">{errors.username.message}</p>
              )}
            </div>

            {/* Phone */}
            <div className="space-y-2">
              <Label htmlFor="phone">{t("labels.phone")} *</Label>
              <Input
                id="phone"
                type="tel"
                placeholder="+225 01 02 03 04"
                {...register("phone")}
              />
              {errors.phone && (
                <p className="text-sm text-destructive">{errors.phone.message}</p>
              )}
            </div>

            {/* Email (optional) */}
            <div className="space-y-2">
              <Label htmlFor="email">{t("profile.email_optional")}</Label>
              <Input
                id="email"
                type="email"
                placeholder="example@gmail.com"
                {...register("email")}
              />
              {errors.email && (
                <p className="text-sm text-destructive">{errors.email.message}</p>
              )}
            </div>

            {/* Country */}
            <div className="space-y-2">
              <Label>{t("labels.country")} *</Label>
              <Select
                value={selectedCountryId}
                onValueChange={(val) => setValue("countryId", val, { shouldValidate: true })}
              >
                <SelectTrigger className="cursor-pointer">
                  <SelectValue placeholder={t("profile.select_country")} />
                </SelectTrigger>
                <SelectContent>
                  {countries.map((c) => (
                    <SelectItem key={c._id} value={c._id} className="cursor-pointer">
                      {c.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {errors.countryId && (
                <p className="text-sm text-destructive">{errors.countryId.message}</p>
              )}
            </div>

            <Button
              type="submit"
              className="w-full cursor-pointer"
              disabled={isSubmitting}
            >
              {isSubmitting ? <Spinner className="mr-2" /> : null}
              {isSubmitting ? t("buttons.saving") : t("profile.complete_btn")}
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  );
}
