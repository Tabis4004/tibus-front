import { useEffect, useState } from "react";
import { useSearchParams, Link, useParams } from "react-router-dom";
import { useAction } from "convex/react";
import { useTranslation } from "react-i18next";
import { api } from "@/convex/_generated/api.js";
import { CheckCircleIcon, XCircleIcon, LoaderIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";

export default function SubscriptionSuccess() {
  const { t } = useTranslation("owner");
  const { lng } = useParams<{ lng: string }>();
  const [searchParams] = useSearchParams();
  const reference = searchParams.get("trxref") ?? searchParams.get("reference") ?? "";
  const [status, setStatus] = useState<"loading" | "success" | "failed">("loading");
  const [planId, setPlanId] = useState<string | null>(null);
  const verifyTx = useAction(api.subscription.verifyPaystackTransaction);

  useEffect(() => {
    if (!reference) {
      setStatus("failed");
      return;
    }
    verifyTx({ reference })
      .then((result) => {
        if (result.success) {
          setStatus("success");
          setPlanId(result.planId ?? null);
        } else {
          setStatus("failed");
        }
      })
      .catch(() => setStatus("failed"));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [reference]);

  return (
    <div className="max-w-md mx-auto px-4 py-16 text-center space-y-5">
      {status === "loading" && (
        <>
          <LoaderIcon className="w-12 h-12 mx-auto text-primary animate-spin" />
          <p className="font-semibold text-lg">{t("sub.verifying")}</p>
          <p className="text-sm text-muted-foreground">{t("sub.verifying_desc")}</p>
        </>
      )}

      {status === "success" && (
        <>
          <div className="w-16 h-16 rounded-full bg-green-500/10 flex items-center justify-center mx-auto">
            <CheckCircleIcon className="w-8 h-8 text-green-500" />
          </div>
          <h1 className="text-2xl font-extrabold">{t("sub.success_title")}</h1>
          <p className="text-muted-foreground text-sm">
            {t("sub.success_desc", { plan: planId ?? "" })}
          </p>
          <div className="flex gap-3 justify-center pt-2">
            <Link to={`/${lng}/owner`}>
              <Button className="cursor-pointer">{t("sub.success_dashboard")}</Button>
            </Link>
          </div>
        </>
      )}

      {status === "failed" && (
        <>
          <div className="w-16 h-16 rounded-full bg-red-500/10 flex items-center justify-center mx-auto">
            <XCircleIcon className="w-8 h-8 text-red-500" />
          </div>
          <h1 className="text-2xl font-extrabold">{t("sub.failed_title")}</h1>
          <p className="text-muted-foreground text-sm">{t("sub.failed_desc")}</p>
          <div className="flex gap-3 justify-center pt-2">
            <Link to={`/${lng}/owner/subscription`}>
              <Button variant="secondary" className="cursor-pointer">{t("sub.try_again")}</Button>
            </Link>
            <Link to={`/${lng}/owner`}>
              <Button className="cursor-pointer">{t("nav.dashboard", { ns: "common" })}</Button>
            </Link>
          </div>
        </>
      )}
    </div>
  );
}
