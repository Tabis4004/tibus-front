# AGENTS.md

## Cursor Cloud specific instructions

### Product overview

**Tibus** is a Vite + React 19 SPA for intercity bus search, booking, and payments (West Africa / XOF). The default stack is **Supabase** (Postgres + Auth + Edge Functions); legacy **Convex + Hercules** remains behind `VITE_AUTH_PROVIDER=hercules`.

### Services

| Service | Required | Start command | URL |
|---------|----------|---------------|-----|
| Vite dev server | Yes | `pnpm dev` | http://localhost:5173 |
| Supabase (hosted) | Yes | Remote project `kqudaqtydimjclwaihqr` — no local `docker-compose` | https://kqudaqtydimjclwaihqr.supabase.co |
| Convex (legacy) | No | `npx convex dev` | http://localhost:3000 |
| Edge Functions | Optional | Deploy via Supabase CLI (see `supabase/DEPLOY_EDGE_FUNCTIONS.md`) | `/functions/v1/*` on project URL |

### Environment variables

Create **`.env.local`** at the repo root (gitignored). Minimum for Supabase mode:

```env
VITE_SUPABASE_URL=https://kqudaqtydimjclwaihqr.supabase.co
VITE_SUPABASE_ANON_KEY=<anon key from Supabase Dashboard → Settings → API>
VITE_AUTH_PROVIDER=supabase
```

If `VITE_SUPABASE_URL` or `VITE_SUPABASE_ANON_KEY` are missing, the app throws at startup (`src/lib/supabase.ts`). Cloud Agent secrets can be written into `.env.local` at session start when those variables are configured in the environment.

Supabase Auth dashboard should allow `http://localhost:5173` and `http://localhost:5173/auth/callback`.

See `SCRIPTS_SUPABASE.md` for SQL migration order and demo data (Abidjan → Yamoussoukro trips).

### Common commands

| Task | Command |
|------|---------|
| Install deps | `pnpm install` |
| Dev server | `pnpm dev` |
| Build | `pnpm run build` |
| Lint | `pnpm run lint` |
| Prettier check | `pnpm run prettier-check` |

There is **no automated test script** in root `package.json`.

### Lint / build notes

- `pnpm run lint` currently reports **1 ESLint error** (pre-existing `no-useless-escape` in the codebase) plus hook dependency warnings.
- `pnpm run build` runs `tsc -b && vite build` and requires `.env.local` with Supabase vars.
- Package manager: **pnpm** (workspace root). Vercel uses `npm ci` per `vercel.json`.

### Hello-world verification

1. Start `pnpm dev`
2. Open `http://localhost:5173/fr/traveler/search`
3. Search **Abidjan → Yamoussoukro** — demo trips from **Tibus Démo Transport** should appear (seeded via `007_seed_demo_data.sql`)

### Gotchas

- Do **not** use the Supabase **service_role** key in `VITE_SUPABASE_ANON_KEY` (client-side). Use the **anon** public key only.
- `pnpm approve-builds` is interactive; `pnpm-workspace.yaml` already lists `onlyBuiltDependencies` for native builds.
- Vite binds `0.0.0.0:5173` (`vite.config.ts`) so the dev server is reachable from the Desktop pane.
- Admin sandbox UI (`ADMIN_SANDBOX_HARDCODED`) grants super_admin in the client only; DB mutations still need real RLS roles.
