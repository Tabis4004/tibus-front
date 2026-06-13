import { getUserFromRequest } from "../_shared/auth.ts";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { createAdminClient, resolveAppUserId } from "../_shared/issue-ticket.ts";

const OWNER_ROLES = [
  "vendeur",
  "chauffeur",
  "comptable_compagnie",
  "controleur",
  "gestionnaire_gare",
] as const;

type ProvisionBody = {
  firstName?: string;
  lastName?: string;
  email?: string;
  phone?: string;
  password?: string;
  roles?: string[];
  companyId?: string;
  countryId?: string;
};

function buildUsername(email: string, authUserId: string) {
  const base = email.split("@")[0]?.replace(/[^a-zA-Z0-9_]/g, "_") ?? "user";
  return `${base}_${authUserId.replace(/-/g, "").slice(0, 12)}`.toLowerCase();
}

async function isSuperAdmin(
  admin: ReturnType<typeof createAdminClient>,
  appUserId: string,
): Promise<boolean> {
  const { data, error } = await admin
    .from("UserRoles")
    .select("Role(name)")
    .eq("userId", appUserId);

  if (error) throw error;

  return (data ?? []).some((row) => {
    const role = Array.isArray(row.Role) ? row.Role[0] : row.Role;
    return (role as { name?: string } | null)?.name === "super_admin";
  });
}

async function ownerCompanyIds(
  admin: ReturnType<typeof createAdminClient>,
  appUserId: string,
): Promise<string[]> {
  const { data, error } = await admin
    .from("UserRoles")
    .select("companyId, Role(name)")
    .eq("userId", appUserId);

  if (error) throw error;

  const ids = new Set<string>();
  for (const row of data ?? []) {
    const role = Array.isArray(row.Role) ? row.Role[0] : row.Role;
    if ((role as { name?: string } | null)?.name === "owner" && row.companyId) {
      ids.add(row.companyId as string);
    }
  }
  return [...ids];
}

async function isOwnerOfCompany(
  admin: ReturnType<typeof createAdminClient>,
  appUserId: string,
  companyId: string,
): Promise<boolean> {
  const { data, error } = await admin
    .from("UserRoles")
    .select("companyId, Role(name)")
    .eq("userId", appUserId)
    .eq("companyId", companyId);

  if (error) throw error;

  return (data ?? []).some((row) => {
    const role = Array.isArray(row.Role) ? row.Role[0] : row.Role;
    return (role as { name?: string } | null)?.name === "owner";
  });
}

function rolesAreOwnerTeamOnly(roles: string[]) {
  return roles.length > 0
    && roles.every((role) => OWNER_ROLES.includes(role as (typeof OWNER_ROLES)[number]));
}

async function resolveCountryId(
  admin: ReturnType<typeof createAdminClient>,
  appUserId: string,
  companyId: string | null,
): Promise<string> {
  if (companyId) {
    const { data: company, error } = await admin
      .from("Companies")
      .select("countryId")
      .eq("id", companyId)
      .maybeSingle();
    if (error) throw error;
    if (company?.countryId) return company.countryId as string;
  }

  const { data: user, error: userError } = await admin
    .from("Users")
    .select("countryId")
    .eq("id", appUserId)
    .maybeSingle();
  if (userError) throw userError;
  if (user?.countryId) return user.countryId as string;

  const { data: countries, error: countriesError } = await admin
    .from("Countries")
    .select("id")
    .limit(1);
  if (countriesError) throw countriesError;
  if (!countries?.length) throw new Error("Aucun pays en base");
  return countries[0].id as string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { user, error: authError } = await getUserFromRequest(req);
    if (authError || !user) {
      return jsonResponse({ error: authError ?? "Session invalide" }, 401);
    }

    const body = (await req.json()) as ProvisionBody;
    const firstName = body.firstName?.trim();
    const lastName = body.lastName?.trim();
    const email = body.email?.trim().toLowerCase();
    const phone = body.phone?.trim() || null;
    const password = body.password?.trim();
    const roles = (body.roles ?? []).map((r) => r.trim()).filter(Boolean);

    if (!firstName || !lastName || !email || !password) {
      return jsonResponse({ error: "Prénom, nom, email et mot de passe requis" }, 400);
    }
    if (password.length < 6) {
      return jsonResponse({ error: "Mot de passe trop court (min. 6 caractères)" }, 400);
    }
    if (!roles.length) {
      return jsonResponse({ error: "Au moins un rôle requis" }, 400);
    }

    const admin = createAdminClient();
    const appUserId = await resolveAppUserId(admin, user.id);
    if (!appUserId) {
      return jsonResponse({ error: "Utilisateur introuvable" }, 403);
    }

    const superAdmin = await isSuperAdmin(admin, appUserId);
    const ownerCompanies = await ownerCompanyIds(admin, appUserId);
    const ownerTeamProvisioning = rolesAreOwnerTeamOnly(roles);

    let companyId: string | null = body.companyId?.trim() || null;
    let countryId: string | null = body.countryId?.trim() || null;

    if (ownerTeamProvisioning) {
      if (companyId) {
        if (
          !superAdmin
          && !ownerCompanies.includes(companyId)
          && !(await isOwnerOfCompany(admin, appUserId, companyId))
        ) {
          return jsonResponse({ error: "Compagnie non autorisée pour ce propriétaire" }, 403);
        }
      } else if (ownerCompanies.length === 1) {
        companyId = ownerCompanies[0];
      } else {
        return jsonResponse({ error: "Sélectionnez une compagnie" }, 400);
      }
    } else if (!superAdmin && !ownerCompanies.length) {
      return jsonResponse({ error: "Droits insuffisants" }, 403);
    } else if (superAdmin) {
      const needsCompany = roles.some((r) =>
        ["owner", "vendeur", "chauffeur", "controleur", "comptable_compagnie"].includes(r)
      );
      if (needsCompany && !companyId) {
        return jsonResponse({ error: "Compagnie requise pour les rôles compagnie" }, 400);
      }
      if (roles.includes("admin_pays") && !countryId) {
        return jsonResponse({ error: "Pays requis pour admin_pays" }, 400);
      }
    } else {
      return jsonResponse({ error: "Droits insuffisants pour ces rôles" }, 403);
    }

    if (ownerTeamProvisioning && !companyId) {
      return jsonResponse({ error: "Compagnie requise pour les rôles compagnie" }, 400);
    }

    if (
      ownerTeamProvisioning
      && companyId
      && !superAdmin
      && !(await isOwnerOfCompany(admin, appUserId, companyId))
    ) {
      return jsonResponse({ error: "Action réservée au propriétaire de la compagnie" }, 403);
    }

    const { data: existingUser } = await admin
      .from("Users")
      .select("id")
      .eq("email", email)
      .maybeSingle();

    if (existingUser) {
      return jsonResponse({ error: "Un utilisateur existe déjà avec cet email" }, 409);
    }

    const { data: authData, error: createAuthError } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { first_name: firstName, last_name: lastName },
    });

    if (createAuthError || !authData.user) {
      const authMsg = createAuthError?.message ?? "Création auth impossible";
      if (/already|exists|registered/i.test(authMsg)) {
        return jsonResponse({ error: "Un compte existe déjà avec cet email" }, 409);
      }
      return jsonResponse({ error: authMsg }, 400);
    }

    const resolvedCountryId = countryId ?? await resolveCountryId(admin, appUserId, companyId);
    const username = buildUsername(email, authData.user.id);

    const { data: profile, error: profileError } = await admin
      .from("Users")
      .insert({
        auth_user_id: authData.user.id,
        firstName,
        lastName,
        username,
        email,
        phone,
        countryId: resolvedCountryId,
        profileCompleted: Boolean(phone),
        onboardingCompleted: Boolean(phone),
      })
      .select("id, firstName, lastName, email")
      .single();

    if (profileError) {
      await admin.auth.admin.deleteUser(authData.user.id);
      const profileMsg = profileError.message ?? "Profil utilisateur impossible";
      if (/duplicate|unique/i.test(profileMsg)) {
        return jsonResponse({ error: "Conflit sur le profil (email ou identifiant déjà utilisé)" }, 409);
      }
      return jsonResponse({ error: profileMsg }, 500);
    }

    const userId = profile.id as string;

    const { data: allRoles, error: rolesError } = await admin
      .from("Role")
      .select("id, name, scope");
    if (rolesError) throw rolesError;

    const roleMap = new Map((allRoles ?? []).map((r) => [r.name as string, r]));

    const toAssign = new Set(roles);
    toAssign.add("traveler");

    const assignedRoles: string[] = [];

    for (const roleName of toAssign) {
      const role = roleMap.get(roleName);
      if (!role) {
        await admin.auth.admin.deleteUser(authData.user.id);
        await admin.from("Users").delete().eq("id", userId);
        return jsonResponse(
          { error: `Rôle introuvable en base : ${roleName}. Vérifiez les migrations SQL (001_roles_model).` },
          500,
        );
      }

      const scope = role.scope as string;
      if (scope === "company" && !companyId) {
        await admin.auth.admin.deleteUser(authData.user.id);
        await admin.from("Users").delete().eq("id", userId);
        return jsonResponse({ error: `Compagnie requise pour le rôle ${roleName}` }, 400);
      }

      const insert = {
        roleId: role.id as string,
        userId,
        companyId: scope === "company" ? companyId : null,
        countryId: roleName === "admin_pays" ? countryId : null,
        assignedBy: appUserId,
      };

      const { error: assignError } = await admin.from("UserRoles").insert(insert);
      if (assignError && !assignError.message.includes("duplicate")) {
        await admin.auth.admin.deleteUser(authData.user.id);
        await admin.from("Users").delete().eq("id", userId);
        return jsonResponse({ error: assignError.message }, 500);
      }
      assignedRoles.push(roleName);
    }

    const requiredCompanyRoles = roles.filter((r) =>
      ["vendeur", "chauffeur", "comptable_compagnie", "controleur", "gestionnaire_gare", "owner"].includes(r)
    );
    const missingRequired = requiredCompanyRoles.filter((r) => !assignedRoles.includes(r));
    if (missingRequired.length > 0) {
      await admin.auth.admin.deleteUser(authData.user.id);
      await admin.from("Users").delete().eq("id", userId);
      return jsonResponse(
        { error: `Échec attribution des rôles : ${missingRequired.join(", ")}` },
        500,
      );
    }

    return jsonResponse({
      success: true,
      user: {
        id: userId,
        firstName: profile.firstName,
        lastName: profile.lastName,
        email: profile.email,
      },
      roles: [...toAssign],
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Erreur création utilisateur";
    return jsonResponse({ error: msg }, 500);
  }
});
