import { supabase } from "@/lib/supabase";
import { listActiveCompaniesSupabase } from "@/lib/supabase/companies.ts";

export type ContactCompanyOption = {
  companyId: string;
  companyName: string;
  whatsappNumber: string | null;
  notificationEmail: string | null;
};

export type OwnerContactSettings = {
  scope: string | null;
  whatsappNumber: string | null;
  notificationEmail: string | null;
  updatedAt?: string | null;
};

export type ContactOptions = {
  platformWhatsapp: string | null;
  platformNotificationEmail: string | null;
  companies: ContactCompanyOption[];
};

export type ContactChannelTarget = {
  whatsappNumber: string | null;
  notificationEmail: string | null;
};

function mapContactOptions(data: Record<string, unknown> | null): ContactOptions {
  const companiesRaw = Array.isArray(data?.companies) ? data.companies : [];
  return {
    platformWhatsapp: data?.platformWhatsapp ? String(data.platformWhatsapp) : null,
    platformNotificationEmail: data?.platformNotificationEmail
      ? String(data.platformNotificationEmail)
      : null,
    companies: companiesRaw
      .map((row) => {
        if (!row || typeof row !== "object") return null;
        const item = row as Record<string, unknown>;
        const companyId = String(item.companyId ?? "");
        const whatsappNumber = item.whatsappNumber ? String(item.whatsappNumber) : null;
        const notificationEmail = item.notificationEmail ? String(item.notificationEmail) : null;
        if (!companyId || (!whatsappNumber && !notificationEmail)) return null;
        return {
          companyId,
          companyName: String(item.companyName ?? "Compagnie"),
          whatsappNumber,
          notificationEmail,
        };
      })
      .filter((row): row is ContactCompanyOption => Boolean(row)),
  };
}

export function getContactTarget(
  contactOptions: ContactOptions | null,
  inquiryTo: string,
): ContactChannelTarget {
  if (!contactOptions) {
    return { whatsappNumber: null, notificationEmail: null };
  }
  if (inquiryTo === "platform") {
    return {
      whatsappNumber: contactOptions.platformWhatsapp,
      notificationEmail: contactOptions.platformNotificationEmail,
    };
  }
  const company = contactOptions.companies.find((c) => c.companyId === inquiryTo);
  return {
    whatsappNumber: company?.whatsappNumber ?? null,
    notificationEmail: company?.notificationEmail ?? null,
  };
}

export function buildWhatsappUrl(number: string, message: string): string {
  const clean = number.replace(/[\s\-()]/g, "");
  return `https://wa.me/${clean}?text=${encodeURIComponent(message)}`;
}

export function buildMailtoUrl(email: string, subject: string, body: string): string {
  const params = new URLSearchParams();
  if (subject) params.set("subject", subject);
  if (body) params.set("body", body);
  const query = params.toString();
  return query ? `mailto:${email}?${query}` : `mailto:${email}`;
}

export async function getContactOptionsSupabase(): Promise<ContactOptions> {
  const { data, error } = await supabase.rpc("get_contact_options");
  if (error) throw error;
  return mapContactOptions((data ?? {}) as Record<string, unknown>);
}

export async function listCompaniesForContactSupabase() {
  return listActiveCompaniesSupabase();
}

export async function getOwnerContactSettingsSupabase(): Promise<OwnerContactSettings> {
  const { data, error } = await supabase.rpc("get_owner_contact_settings");
  if (error) throw error;
  const row = (data ?? {}) as Record<string, unknown>;
  return {
    scope: row.scope ? String(row.scope) : null,
    whatsappNumber: row.whatsappNumber ? String(row.whatsappNumber) : null,
    notificationEmail: row.notificationEmail ? String(row.notificationEmail) : null,
    updatedAt: row.updatedAt ? String(row.updatedAt) : null,
  };
}

export async function setContactSettingsSupabase(
  scope: string,
  input: { whatsappNumber?: string; notificationEmail?: string },
): Promise<void> {
  const { error } = await supabase.rpc("set_contact_settings", {
    p_scope: scope,
    p_whatsapp_number: input.whatsappNumber?.trim() || null,
    p_notification_email: input.notificationEmail?.trim() || null,
  });
  if (error) throw error;
}
