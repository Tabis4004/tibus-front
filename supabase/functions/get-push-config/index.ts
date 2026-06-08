import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const publicKey = Deno.env.get("VAPID_PUBLIC_KEY");
  if (!publicKey) {
    return jsonResponse({ error: "Notifications push non configurées" }, 503);
  }

  return jsonResponse({ vapidPublicKey: publicKey });
});
