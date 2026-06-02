import { useState } from "react";

const PUSH_OPTIN_DISMISSED_KEY = "push-optin-dismissed";
const PUSH_OPTIN_BOOKING_COUNT_KEY = "push-optin-booking-count";

/**
 * Hook for triggering push notification opt-in prompt after first booking.
 * Call `triggerAfterBooking()` from the booking confirmation to display the prompt.
 */
export function usePushOptIn() {
  const [showPrompt, setShowPrompt] = useState(false);

  const triggerAfterBooking = () => {
    // Don't show if already dismissed or subscribed
    const dismissed = localStorage.getItem(PUSH_OPTIN_DISMISSED_KEY);
    const secret = localStorage.getItem("push-subscription-secret");
    if (dismissed || secret) return;

    // Count bookings
    const count = parseInt(localStorage.getItem(PUSH_OPTIN_BOOKING_COUNT_KEY) ?? "0", 10);
    const newCount = count + 1;
    localStorage.setItem(PUSH_OPTIN_BOOKING_COUNT_KEY, String(newCount));

    // Show after first booking
    if (newCount >= 1) {
      setShowPrompt(true);
    }
  };

  const dismiss = () => {
    setShowPrompt(false);
    localStorage.setItem(PUSH_OPTIN_DISMISSED_KEY, "true");
  };

  return { showPrompt, triggerAfterBooking, dismiss, setShowPrompt };
}
