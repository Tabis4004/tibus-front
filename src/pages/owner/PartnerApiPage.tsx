import { useCallback, useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { KeyIcon, CopyIcon, LinkIcon, WebhookIcon } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { useOwnerCompany } from "@/hooks/use-owner-company.tsx";
import {
  createPartnerApiKeySupabase,
  createPartnerWebhookSupabase,
  listPartnerApiKeysSupabase,
  listPartnerWebhookDeliveriesSupabase,
  listPartnerWebhooksSupabase,
  partnerItineraryApiBaseUrl,
  type PartnerApiKeyRow,
  type PartnerWebhookDeliveryRow,
  type PartnerWebhookRow,
} from "@/lib/supabase/partner-itinerary.ts";

export default function PartnerApiPage() {
  const { t } = useTranslation("owner");
  const { appUserId } = useSupabaseAuth();
  const { companyId, isReady: companyReady } = useOwnerCompany();
  const [keys, setKeys] = useState<PartnerApiKeyRow[] | undefined>(undefined);
  const [name, setName] = useState("");
  const [externalSystem, setExternalSystem] = useState("default");
  const [freshKey, setFreshKey] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [webhooks, setWebhooks] = useState<PartnerWebhookRow[] | undefined>(undefined);
  const [deliveries, setDeliveries] = useState<PartnerWebhookDeliveryRow[] | undefined>(undefined);
  const [webhookUrl, setWebhookUrl] = useState("");
  const [freshWebhookSecret, setFreshWebhookSecret] = useState<string | null>(null);
  const [webhookSaving, setWebhookSaving] = useState(false);

  const loadKeys = useCallback(async () => {
    if (!appUserId || !companyId || !companyReady) return;
    setKeys(undefined);
    try {
      const rows = await listPartnerApiKeysSupabase(appUserId, companyId);
      setKeys(rows);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("partner_api.load_error"));
      setKeys([]);
    }
  }, [appUserId, companyId, companyReady, t]);

  const loadWebhooks = useCallback(async () => {
    if (!appUserId || !companyId || !companyReady) return;
    setWebhooks(undefined);
    setDeliveries(undefined);
    try {
      const [hookRows, deliveryRows] = await Promise.all([
        listPartnerWebhooksSupabase(appUserId, companyId),
        listPartnerWebhookDeliveriesSupabase(appUserId, companyId),
      ]);
      setWebhooks(hookRows);
      setDeliveries(deliveryRows);
    } catch {
      setWebhooks([]);
      setDeliveries([]);
    }
  }, [appUserId, companyId, companyReady]);

  useEffect(() => {
    void loadKeys();
    void loadWebhooks();
  }, [loadKeys, loadWebhooks]);

  const handleCreate = async () => {
    if (!appUserId || !companyId || name.trim().length < 2) return;
    setSaving(true);
    try {
      const created = await createPartnerApiKeySupabase({
        appUserId,
        companyId,
        name: name.trim(),
        externalSystem: externalSystem.trim() || "default",
      });
      setFreshKey(created.apiKey);
      setName("");
      toast.success(t("partner_api.created"));
      await loadKeys();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("partner_api.create_error"));
    } finally {
      setSaving(false);
    }
  };

  const apiBase = partnerItineraryApiBaseUrl();

  return (
    <div className="max-w-3xl mx-auto px-4 py-6 space-y-5">
      <div>
        <h1 className="text-2xl font-extrabold tracking-tight">{t("partner_api.title")}</h1>
        <p className="text-muted-foreground text-sm mt-1">{t("partner_api.desc")}</p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <LinkIcon className="w-4 h-4" />
            {t("partner_api.endpoint_title")}
          </CardTitle>
          <CardDescription>{t("partner_api.endpoint_desc")}</CardDescription>
        </CardHeader>
        <CardContent className="space-y-2 text-sm">
          <code className="block rounded-lg bg-muted px-3 py-2 break-all">{apiBase || "—"}</code>
          <ul className="list-disc pl-5 space-y-1 text-muted-foreground">
            <li>{t("partner_api.route_mappings")}</li>
            <li>{t("partner_api.route_departures")}</li>
            <li>{t("partner_api.route_availability")}</li>
            <li>{t("partner_api.route_bookings")}</li>
            <li>{t("partner_api.route_webhooks")}</li>
          </ul>
          <p className="text-xs text-muted-foreground pt-1">
            {t("partner_api.docs_hint")}{" "}
            <code className="text-foreground">docs/PARTNER_ITINERARY_API.md</code>
          </p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <KeyIcon className="w-4 h-4" />
            {t("partner_api.create_title")}
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="grid gap-3 sm:grid-cols-2">
            <div className="space-y-1.5">
              <Label>{t("partner_api.key_name")}</Label>
              <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="ERP compagnie X" />
            </div>
            <div className="space-y-1.5">
              <Label>{t("partner_api.external_system")}</Label>
              <Input
                value={externalSystem}
                onChange={(e) => setExternalSystem(e.target.value)}
                placeholder="default"
              />
            </div>
          </div>
          <Button onClick={handleCreate} disabled={saving || name.trim().length < 2}>
            {saving ? t("partner_api.creating") : t("partner_api.create_button")}
          </Button>

          {freshKey ? (
            <div className="rounded-xl border border-amber-500/40 bg-amber-500/5 p-3 space-y-2">
              <p className="text-sm font-medium">{t("partner_api.copy_once")}</p>
              <code className="block rounded bg-background px-2 py-1 text-xs break-all">{freshKey}</code>
              <Button
                size="sm"
                variant="secondary"
                onClick={async () => {
                  await navigator.clipboard.writeText(freshKey);
                  toast.success(t("partner_api.copied"));
                }}
              >
                <CopyIcon className="w-4 h-4 mr-1.5" />
                {t("partner_api.copy_button")}
              </Button>
            </div>
          ) : null}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">{t("partner_api.keys_title")}</CardTitle>
        </CardHeader>
        <CardContent>
          {keys === undefined ? (
            <div className="space-y-2">
              <Skeleton className="h-14 rounded-lg" />
              <Skeleton className="h-14 rounded-lg" />
            </div>
          ) : keys.length === 0 ? (
            <p className="text-sm text-muted-foreground">{t("partner_api.empty")}</p>
          ) : (
            <div className="space-y-2">
              {keys.map((key) => (
                <div key={key.id} className="rounded-xl border p-3 flex items-center justify-between gap-3">
                  <div className="min-w-0">
                    <div className="font-medium text-sm truncate">{key.name}</div>
                    <div className="text-xs text-muted-foreground mt-0.5">
                      {key.keyPrefix}… · {key.externalSystem}
                    </div>
                  </div>
                  <Badge variant={key.isActive ? "default" : "secondary"}>
                    {key.isActive ? t("partner_api.active") : t("partner_api.inactive")}
                  </Badge>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <WebhookIcon className="w-4 h-4" />
            {t("partner_api.webhooks_title")}
          </CardTitle>
          <CardDescription>{t("partner_api.webhooks_desc")}</CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="space-y-1.5">
            <Label>{t("partner_api.webhook_url")}</Label>
            <Input
              value={webhookUrl}
              onChange={(e) => setWebhookUrl(e.target.value)}
              placeholder="https://votre-erp.com/tibus/webhook"
            />
          </div>
          <Button
            onClick={async () => {
              if (!appUserId || !companyId || webhookUrl.trim().length < 8) return;
              setWebhookSaving(true);
              try {
                const created = await createPartnerWebhookSupabase({
                  appUserId,
                  companyId,
                  url: webhookUrl.trim(),
                  externalSystem,
                });
                setFreshWebhookSecret(created.secret);
                setWebhookUrl("");
                toast.success(t("partner_api.webhook_created"));
                await loadWebhooks();
              } catch (err) {
                toast.error(err instanceof Error ? err.message : t("partner_api.webhook_error"));
              } finally {
                setWebhookSaving(false);
              }
            }}
            disabled={webhookSaving || webhookUrl.trim().length < 8}
          >
            {webhookSaving ? t("partner_api.webhook_creating") : t("partner_api.webhook_create")}
          </Button>

          {freshWebhookSecret ? (
            <div className="rounded-xl border border-amber-500/40 bg-amber-500/5 p-3 space-y-2">
              <p className="text-sm font-medium">{t("partner_api.webhook_secret_once")}</p>
              <code className="block rounded bg-background px-2 py-1 text-xs break-all">{freshWebhookSecret}</code>
            </div>
          ) : null}

          {webhooks === undefined ? (
            <Skeleton className="h-14 rounded-lg" />
          ) : webhooks.length === 0 ? (
            <p className="text-sm text-muted-foreground">{t("partner_api.webhooks_empty")}</p>
          ) : (
            <div className="space-y-2">
              {webhooks.map((hook) => (
                <div key={hook.id} className="rounded-xl border p-3 text-sm">
                  <div className="font-medium break-all">{hook.url}</div>
                  <div className="text-xs text-muted-foreground mt-1">
                    {hook.externalSystem} · {(hook.events ?? []).join(", ")}
                  </div>
                </div>
              ))}
            </div>
          )}

          {deliveries && deliveries.length > 0 ? (
            <div className="pt-2 space-y-2">
              <p className="text-sm font-medium">{t("partner_api.deliveries_title")}</p>
              {deliveries.slice(0, 5).map((delivery) => (
                <div key={delivery.id} className="text-xs text-muted-foreground border rounded-lg p-2">
                  <span className="font-mono">{delivery.eventType}</span>
                  {" · "}
                  HTTP {delivery.responseStatus ?? "—"}
                  {" · "}
                  {new Date(delivery.deliveredAt).toLocaleString()}
                </div>
              ))}
            </div>
          ) : null}
        </CardContent>
      </Card>
    </div>
  );
}
