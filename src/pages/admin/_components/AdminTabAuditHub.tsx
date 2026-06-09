import AdminAuditHub from "./AdminAuditHub.tsx";
import {
  ADMIN_TAB_AUDIT_MODULE_KEYS,
  type AdminPanelTabId,
} from "./admin-audit-module-keys.ts";

export default function AdminTabAuditHub({ tab }: { tab: AdminPanelTabId }) {
  return (
    <AdminAuditHub
      moduleKey={ADMIN_TAB_AUDIT_MODULE_KEYS[tab]}
      scopeLabel={tab}
      className="mt-4"
    />
  );
}
