// POST /functions/v1/app-store-notifications   (App Store Server Notifications V2)
// Apple calls this URL (set in App Store Connect › App Information). No user
// JWT: authenticity comes from verifying the signed payload with Apple's
// certificate chain. REFUND / REVOKE take the entitlement back in the ledger.
import { createClient } from "npm:@supabase/supabase-js@2.49.4";
import { fail, json, readJson } from "../_shared/http.ts";
import { makeVerifier } from "../_shared/apple.ts";
import { BUNDLE_ID, REVOKING_NOTIFICATIONS } from "../_shared/purchases.ts";

Deno.serve(async (req) => {
  const body = await readJson(req, 64_000);
  const signedPayload = typeof body?.signedPayload === "string" ? body.signedPayload : "";
  if (!signedPayload) return fail(400, "invalid_payload");
  const verifier = makeVerifier();
  if (!verifier) return fail(503, "verification_not_configured");

  let notification;
  try {
    notification = await verifier.verifyAndDecodeNotification(signedPayload);
  } catch {
    return fail(400, "invalid_signature");
  }
  if (notification.data?.bundleId !== BUNDLE_ID) return fail(403, "wrong_bundle");
  // Acknowledge everything else (Apple retries non-2xx responses).
  if (!REVOKING_NOTIFICATIONS.has(String(notification.notificationType))) return json(200, { status: "ignored" });

  const signedTx = notification.data?.signedTransactionInfo;
  if (!signedTx) return fail(400, "missing_transaction");
  let tx;
  try {
    tx = await verifier.verifyAndDecodeTransaction(signedTx);
  } catch {
    return fail(400, "invalid_signature");
  }
  if (!tx.transactionId) return fail(400, "invalid_transaction");

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const { data, error } = await admin.rpc("revoke_purchase", {
    p_transaction_id: tx.transactionId,
    p_revoked_at: new Date(tx.revocationDate ?? Date.now()).toISOString(),
  });
  if (error) return fail(500, "internal_error");
  return json(200, { status: data ?? "unknown" });
});
