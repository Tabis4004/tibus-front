import { createAdminClient } from "./issue-ticket.ts";

export type PartnerAuthContext = {
  keyId: string;
  companyId: string;
  externalSystem: string;
};

function readApiKey(req: Request): string | null {
  const headerKey = req.headers.get("x-api-key")?.trim();
  if (headerKey) return headerKey;

  const auth = req.headers.get("authorization")?.trim() ?? "";
  if (auth.toLowerCase().startsWith("bearer ")) {
    return auth.slice(7).trim();
  }

  return null;
}

export async function resolvePartnerAuth(
  req: Request,
): Promise<{ context: PartnerAuthContext | null; error: string | null }> {
  const apiKey = readApiKey(req);
  if (!apiKey) {
    return { context: null, error: "Cle API manquante (X-Api-Key ou Authorization Bearer)" };
  }

  const admin = createAdminClient();
  const { data, error } = await admin.rpc("partner_resolve_api_key", {
    p_api_key: apiKey,
  });

  if (error) {
    return { context: null, error: error.message };
  }

  const row = Array.isArray(data) ? data[0] : null;
  if (!row) {
    return { context: null, error: "Cle API invalide ou desactivee" };
  }

  return {
    context: {
      keyId: row.key_id as string,
      companyId: row.company_id as string,
      externalSystem: row.external_system as string,
    },
    error: null,
  };
}
