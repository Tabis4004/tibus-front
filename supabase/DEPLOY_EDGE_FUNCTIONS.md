# Déployer les Edge Functions FedaPay

## Option A — Terminal (recommandé)

```bash
cd /Users/tabistabis.tg/Documents/tibus-front
export SUPABASE_ACCESS_TOKEN='sbp_VOTRE_TOKEN'
npx supabase functions deploy fedapay-initialize
npx supabase functions deploy fedapay-verify
npx supabase functions deploy fedapay-webhook
```

`verify_jwt` est `false` dans `supabase/config.toml` pour initialize et verify.

## Option B — Dashboard (patch auth)

Si vous déployez via le Dashboard (un seul fichier `index.ts`), remplacez le bloc auth par :

```typescript
const authHeader = req.headers.get("Authorization");
if (!authHeader?.startsWith("Bearer ")) {
  return jsonResponse({ error: "Non authentifié" }, 401);
}
const jwt = authHeader.slice(7).trim();
const authClient = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_ANON_KEY")!,
);
const { data: { user }, error: userError } = await authClient.auth.getUser(jwt);
if (userError || !user) {
  return jsonResponse({ error: userError?.message ?? "Session invalide" }, 401);
}
```

**Ne pas** utiliser `getUser()` sans argument avec `global: { headers: { Authorization } }` — cela provoque `Invalid credentials`.

JWT verification : **OFF** sur `fedapay-initialize` et `fedapay-verify`, puis **Redeploy**.
