import { lazy } from "react";

export const GatewayFeeSettingsPanel = lazy(
  () => import("./_components/GatewayFeeSettingsPanel.tsx"),
);
export const StakeholderCommissionPanel = lazy(
  () => import("./_components/StakeholderCommissionPanel.tsx"),
);
export const PaymentGatewaySettingsPanel = lazy(
  () => import("./_components/PaymentGatewaySettingsPanel.tsx"),
);
export const TravelerBookingNoticePanel = lazy(
  () => import("./_components/TravelerBookingNoticePanel.tsx"),
);
export const GuaranteeFundManager = lazy(() => import("./_components/GuaranteeFundManager.tsx"));
export const ContactSettingsPanel = lazy(() => import("./_components/ContactSettingsPanel.tsx"));
export const PlatformLoyaltySettingsPanel = lazy(
  () => import("./_components/PlatformLoyaltySettingsPanel.tsx"),
);
export const LegalPagesPanel = lazy(() => import("./_components/LegalPagesPanel.tsx"));
export const PlatformScalingMetricsPanel = lazy(
  () => import("./_components/PlatformScalingMetricsPanel.tsx"),
);
export const InvestorPlanPanel = lazy(() => import("./_components/InvestorPlanPanel.tsx"));
export const TpePosDiagnosticsPanel = lazy(
  () => import("./_components/TpePosDiagnosticsPanel.tsx"),
);
export const SupabasePlansTab = lazy(() => import("./_components/SupabasePlansTab.tsx"));
export const SupabaseSubscriptionsTab = lazy(
  () => import("./_components/SupabaseSubscriptionsTab.tsx"),
);
