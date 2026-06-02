import { useEffect, useState } from "react";
import { BellRingIcon, XIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { usePushNotifications } from "@/hooks/use-push-notifications.ts";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { motion, AnimatePresence } from "motion/react";

type PushOptInPromptProps = {
  show: boolean;
  onDismiss: () => void;
};

export default function PushOptInPrompt({ show, onDismiss }: PushOptInPromptProps) {
  const { t } = useTranslation("common");
  const { status, subscribe } = usePushNotifications();
  const [isSubscribing, setIsSubscribing] = useState(false);

  // Auto-dismiss if already subscribed or unsupported
  useEffect(() => {
    if (status === "subscribed" || status === "unsupported" || status === "denied") {
      onDismiss();
    }
  }, [status, onDismiss]);

  const handleEnable = async () => {
    setIsSubscribing(true);
    const result = await subscribe();
    setIsSubscribing(false);

    if (result && "subscribed" in result && result.subscribed) {
      toast.success(t("notifications.push_enabled"));
      onDismiss();
    } else if (result && "permission" in result && result.permission === "denied") {
      toast.error(t("notifications.push_denied"));
      onDismiss();
    }
  };

  if (status === "subscribed" || status === "unsupported" || status === "iframe") {
    return null;
  }

  return (
    <AnimatePresence>
      {show && (
        <motion.div
          initial={{ opacity: 0, y: 50, scale: 0.95 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={{ opacity: 0, y: 50, scale: 0.95 }}
          transition={{ duration: 0.3, ease: "easeOut" }}
          className="fixed bottom-20 left-4 right-4 md:left-auto md:right-6 md:bottom-6 md:w-80 z-50"
        >
          <div className="bg-card border shadow-lg rounded-xl p-4 relative">
            <button
              onClick={onDismiss}
              className="absolute top-2 right-2 p-1 rounded-full hover:bg-muted transition-colors cursor-pointer"
            >
              <XIcon className="w-4 h-4 text-muted-foreground" />
            </button>

            <div className="flex items-start gap-3">
              <div className="p-2 rounded-full bg-primary/10 text-primary flex-shrink-0">
                <BellRingIcon className="w-5 h-5" />
              </div>
              <div className="flex-1 min-w-0">
                <h4 className="font-semibold text-sm text-foreground">
                  {t("notifications.optin_title")}
                </h4>
                <p className="text-xs text-muted-foreground mt-0.5 leading-relaxed">
                  {t("notifications.optin_description")}
                </p>
                <div className="flex items-center gap-2 mt-3">
                  <Button
                    size="sm"
                    className="h-7 text-xs cursor-pointer"
                    onClick={handleEnable}
                    disabled={isSubscribing}
                  >
                    {t("notifications.optin_enable")}
                  </Button>
                  <Button
                    variant="ghost"
                    size="sm"
                    className="h-7 text-xs cursor-pointer"
                    onClick={onDismiss}
                  >
                    {t("notifications.optin_later")}
                  </Button>
                </div>
              </div>
            </div>
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
