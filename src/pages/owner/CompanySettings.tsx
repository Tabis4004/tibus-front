import { useState, useEffect, useCallback, useRef } from "react";
import { useQuery, useMutation } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import { useTranslation } from "react-i18next";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { toast } from "sonner";
import { useNavigate, useParams } from "react-router-dom";
import { BuildingIcon, SaveIcon, GlobeIcon, PhoneIcon, MailIcon, ImageIcon, UploadCloudIcon, XIcon, FileTextIcon, LandmarkIcon } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Textarea } from "@/components/ui/textarea.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import type { Id } from "@/convex/_generated/dataModel.d.ts";

const companySchema = z.object({
  name: z.string().min(2, "Company name must be at least 2 characters"),
  description: z.string().max(500).optional(),
  phone: z.string().optional(),
  email: z.string().email("Must be a valid email").optional().or(z.literal("")),
  website: z.string().url("Must be a valid URL").optional().or(z.literal("")),
  boardingMessage: z.string().max(300).optional(),
  nif: z.string().optional(),
  rccm: z.string().optional(),
  tva: z.string().optional(),
  bankAccount: z.string().optional(),
});

type CompanyFormData = z.infer<typeof companySchema>;

export default function CompanySettings() {
  const { t } = useTranslation("owner");
  const { lng } = useParams<{ lng: string }>();
  const navigate = useNavigate();
  const company = useQuery(api.companies.getMyCompany, {});
  const createCompany = useMutation(api.companies.createCompany);
  const updateCompany = useMutation(api.companies.updateCompany);
  const generateUploadUrl = useMutation(api.companies.generateUploadUrl);
  const [saving, setSaving] = useState(false);
  const isNew = company === null || company === undefined;

  // Logo upload state
  const [logoStorageId, setLogoStorageId] = useState<Id<"_storage"> | null>(null);
  const [logoPreviewUrl, setLogoPreviewUrl] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  const [dragOver, setDragOver] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Get logo URL from storage if company has one
  const existingLogoUrl = useQuery(
    api.companies.getLogoUrl,
    company?.logoStorageId ? { storageId: company.logoStorageId } : "skip",
  );

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors, isDirty },
  } = useForm<CompanyFormData>({
    resolver: zodResolver(companySchema),
    defaultValues: {
      name: "",
      description: "",
      phone: "",
      email: "",
      website: "",
      boardingMessage: "",
    },
  });

  useEffect(() => {
    if (company) {
      reset({
        name: company.name ?? "",
        description: company.description ?? "",
        phone: company.phone ?? "",
        email: company.email ?? "",
        website: company.website ?? "",
        boardingMessage: company.boardingMessage ?? "",
        nif: company.nif ?? "",
        rccm: company.rccm ?? "",
        tva: company.tva ?? "",
        bankAccount: company.bankAccount ?? "",
      });
      if (company.logoStorageId) {
        setLogoStorageId(company.logoStorageId);
      }
    }
  }, [company, reset]);

  // Resolve logo display URL
  const displayLogoUrl = logoPreviewUrl ?? existingLogoUrl ?? company?.logoUrl ?? null;

  const handleFileUpload = useCallback(async (file: File) => {
    if (!file.type.startsWith("image/")) {
      toast.error(t("company.logo_invalid_type"));
      return;
    }
    if (file.size > 5 * 1024 * 1024) {
      toast.error(t("company.logo_too_large"));
      return;
    }

    setUploading(true);
    try {
      const uploadUrl = await generateUploadUrl();
      const result = await fetch(uploadUrl, {
        method: "POST",
        headers: { "Content-Type": file.type },
        body: file,
      });
      const { storageId } = (await result.json()) as { storageId: Id<"_storage"> };
      setLogoStorageId(storageId);
      // Create local preview
      setLogoPreviewUrl(URL.createObjectURL(file));
      toast.success(t("company.logo_uploaded"));
    } catch {
      toast.error(t("company.logo_upload_error"));
    } finally {
      setUploading(false);
    }
  }, [generateUploadUrl, t]);

  const handleDrop = useCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    setDragOver(false);
    const file = e.dataTransfer.files[0];
    if (file) handleFileUpload(file);
  }, [handleFileUpload]);

  const handleDragOver = useCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    setDragOver(true);
  }, []);

  const handleDragLeave = useCallback(() => {
    setDragOver(false);
  }, []);

  const handleFileInput = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) handleFileUpload(file);
  }, [handleFileUpload]);

  const removeLogo = useCallback(() => {
    setLogoStorageId(null);
    setLogoPreviewUrl(null);
    if (fileInputRef.current) fileInputRef.current.value = "";
  }, []);

  const onSubmit = async (data: CompanyFormData) => {
    setSaving(true);
    try {
      const payload = {
        name: data.name,
        description: data.description || undefined,
        logoStorageId: logoStorageId ?? undefined,
        logoUrl: undefined as string | undefined,
        phone: data.phone || undefined,
        email: data.email || undefined,
        website: data.website || undefined,
        boardingMessage: data.boardingMessage || undefined,
        nif: data.nif || undefined,
        rccm: data.rccm || undefined,
        tva: data.tva || undefined,
        bankAccount: data.bankAccount || undefined,
      };
      if (isNew) {
        await createCompany(payload);
        toast.success(t("company.created"));
        navigate(`/${lng}/owner`, { replace: true });
      } else {
        await updateCompany({ companyId: company._id, ...payload });
        toast.success(t("company.updated"));
      }
    } catch {
      toast.error(t("company.save_error"));
    } finally {
      setSaving(false);
    }
  };

  if (company === undefined) {
    return (
      <div className="max-w-2xl mx-auto px-4 py-6 space-y-4">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-64 w-full rounded-xl" />
      </div>
    );
  }

  const hasUnsavedLogo = logoStorageId !== company?.logoStorageId;

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 space-y-6">
      <div>
        <h1 className="text-2xl font-extrabold tracking-tight">
          {isNew ? t("company.create_title") : t("company.settings_title")}
        </h1>
        <p className="text-muted-foreground text-sm mt-1">
          {isNew ? t("company.create_desc") : t("company.settings_desc")}
        </p>
      </div>

      <form onSubmit={handleSubmit(onSubmit)} className="space-y-5">
        {/* Logo upload (drag & drop) */}
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-semibold flex items-center gap-2">
              <ImageIcon className="w-4 h-4" /> {t("company.logo")}
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <div
              onDrop={handleDrop}
              onDragOver={handleDragOver}
              onDragLeave={handleDragLeave}
              onClick={() => fileInputRef.current?.click()}
              className={`relative flex flex-col items-center justify-center rounded-xl border-2 border-dashed p-6 transition-colors cursor-pointer ${
                dragOver
                  ? "border-primary bg-primary/5"
                  : "border-border bg-muted/30 hover:border-primary/50"
              }`}
            >
              {displayLogoUrl ? (
                <div className="relative">
                  <img
                    src={displayLogoUrl}
                    alt="Company logo"
                    className="w-24 h-24 rounded-xl object-cover border shadow-sm"
                  />
                  <button
                    type="button"
                    onClick={(e) => { e.stopPropagation(); removeLogo(); }}
                    className="absolute -top-2 -right-2 w-6 h-6 rounded-full bg-destructive text-destructive-foreground flex items-center justify-center shadow cursor-pointer"
                  >
                    <XIcon className="w-3.5 h-3.5" />
                  </button>
                </div>
              ) : (
                <>
                  <UploadCloudIcon className="w-10 h-10 text-muted-foreground mb-2" />
                  <p className="text-sm font-medium text-foreground">{t("company.logo_drag")}</p>
                  <p className="text-[11px] text-muted-foreground mt-1">{t("company.logo_formats")}</p>
                </>
              )}
              {uploading && (
                <div className="absolute inset-0 flex items-center justify-center bg-background/60 rounded-xl">
                  <p className="text-sm font-medium animate-pulse">{t("company.logo_uploading")}</p>
                </div>
              )}
            </div>
            <input
              ref={fileInputRef}
              type="file"
              accept="image/*"
              className="hidden"
              onChange={handleFileInput}
            />
          </CardContent>
        </Card>

        {/* Basic Info */}
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-semibold flex items-center gap-2">
              <BuildingIcon className="w-4 h-4" /> {t("company.basic_info")}
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-1.5">
              <Label htmlFor="name">{t("company.name")} <span className="text-destructive">*</span></Label>
              <Input id="name" placeholder="e.g. Swift Express Bus Co." {...register("name")} />
              {errors.name && <p className="text-xs text-destructive">{errors.name.message}</p>}
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="description">{t("company.description")}</Label>
              <Textarea
                id="description"
                placeholder={t("company.description_placeholder")}
                rows={3}
                {...register("description")}
              />
              {errors.description && <p className="text-xs text-destructive">{errors.description.message}</p>}
            </div>
          </CardContent>
        </Card>

        {/* Contact Info */}
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-semibold">{t("company.contact")}</CardTitle>
            <CardDescription className="text-xs">{t("company.contact_desc")}</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-1.5">
              <Label htmlFor="phone" className="flex items-center gap-1.5">
                <PhoneIcon className="w-3.5 h-3.5" /> {t("company.phone")}
              </Label>
              <Input id="phone" placeholder="+1 555 000 0000" {...register("phone")} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="email" className="flex items-center gap-1.5">
                <MailIcon className="w-3.5 h-3.5" /> {t("company.email")}
              </Label>
              <Input id="email" placeholder="contact@mycompany.com" {...register("email")} />
              {errors.email && <p className="text-xs text-destructive">{errors.email.message}</p>}
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="website" className="flex items-center gap-1.5">
                <GlobeIcon className="w-3.5 h-3.5" /> {t("company.website")}
              </Label>
              <Input id="website" placeholder="https://mycompany.com" {...register("website")} />
              {errors.website && <p className="text-xs text-destructive">{errors.website.message}</p>}
            </div>
          </CardContent>
        </Card>

        {/* Fiscal & Banking Info */}
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-semibold flex items-center gap-2">
              <FileTextIcon className="w-4 h-4" /> {t("company.fiscal_info", { defaultValue: "Fiscal & Banking Info" })}
            </CardTitle>
            <CardDescription className="text-xs">
              {t("company.fiscal_info_desc", { defaultValue: "These details appear on corporate receipts when TVA is applied during a sale." })}
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div className="space-y-1.5">
                <Label htmlFor="nif">NIF</Label>
                <Input id="nif" placeholder="e.g. 1234567890" {...register("nif")} />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="rccm">RCCM</Label>
                <Input id="rccm" placeholder="e.g. CI-ABJ-2024-B-12345" {...register("rccm")} />
              </div>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="tva">{t("company.tva_rate", { defaultValue: "TVA (%)" })}</Label>
              <Input id="tva" placeholder="e.g. 18" {...register("tva")} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="bankAccount" className="flex items-center gap-1.5">
                <LandmarkIcon className="w-3.5 h-3.5" /> {t("company.bank_account", { defaultValue: "Bank Account" })}
              </Label>
              <Input id="bankAccount" placeholder="e.g. IBAN or local account number" {...register("bankAccount")} />
            </div>
          </CardContent>
        </Card>

        <Button type="submit" className="w-full" disabled={saving || (!isDirty && !isNew && !hasUnsavedLogo)}>
          <SaveIcon className="w-4 h-4 mr-2" />
          {saving
            ? t("buttons.saving", { ns: "common" })
            : isNew
            ? t("company.create_btn")
            : t("company.save_btn")}
        </Button>
      </form>
    </div>
  );
}
