// POST /functions/v1/app-store-notifications   (App Store Server Notifications V2)
// Apple calls this URL (set in App Store Connect › App Information). No user
// JWT: authenticity comes from verifying the signed payload with Apple's
// certificate chain. Notifications are durably deduplicated by notificationUUID;
// REFUND / REVOKE remove and REFUND_REVERSED reinstates the entitlement.
import { createClient } from "npm:@supabase/supabase-js@2.49.4";
import { fail, json, readJson } from "../_shared/http.ts";
import { makeVerifierSet } from "../_shared/apple.ts";
import {
  BUNDLE_ID,
  REINSTATING_NOTIFICATIONS,
  REVOKING_NOTIFICATIONS,
} from "../_shared/purchases.ts";

Deno.serve(async (req) => {
  const body = await readJson(req, 64_000);
  const signedPayload = typeof body?.signedPayload === "string"
    ? body.signedPayload
    : "";
  if (!signedPayload) return fail(400, "invalid_payload");
  const verifier = makeVerifierSet();
  if (!verifier) return fail(503, "verification_not_configured");

  let notification;
  try {
    notification = await verifier.verifyAndDecodeNotification(signedPayload);
  } catch {
    return fail(400, "invalid_signature");
  }
  if (notification.data?.bundleId !== BUNDLE_ID) {
    return fail(403, "wrong_bundle");
  }
  const notificationType = String(notification.notificationType ?? "");
  const notificationUUID = String(notification.notificationUUID ?? "");
  if (!notificationUUID || !notificationType) {
    return fail(400, "invalid_notification");
  }
  const actionable = REVOKING_NOTIFICATIONS.has(notificationType) ||
    REINSTATING_NOTIFICATIONS.has(notificationType);

  const signedTx = notification.data?.signedTransactionInfo;
  let tx:
    | Awaited<ReturnType<typeof verifier.verifyAndDecodeTransaction>>
    | null = null;
  if (actionable) {
    if (!signedTx) return fail(400, "missing_transaction");
    try {
      tx = await verifier.verifyAndDecodeTransaction(signedTx);
    } catch {
      return fail(400, "invalid_signature");
    }
    if (!tx.transactionId) return fail(400, "invalid_transaction");
  }

  const secret = Deno.env.get("SUPABASE_SECRET_KEY") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!secret) return fail(503, "server_not_configured");
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, secret, {
    auth: { persistSession: false },
  });
  const token =
    tx?.appAccountToken && /^[0-9a-f-]{36}$/i.test(tx.appAccountToken)
      ? tx.appAccountToken
      : null;
  const { data, error } = await admin.rpc("process_app_store_notification", {
    p_notification_uuid: notificationUUID,
    p_notification_type: notificationType,
    p_subtype: notification.subtype ? String(notification.subtype) : null,
    p_signed_at: new Date(notification.signedDate ?? Date.now()).toISOString(),
    p_transaction_id: tx?.transactionId ?? null,
    p_original_transaction_id: tx?.originalTransactionId ?? null,
    p_product_id: tx?.productId ?? null,
    p_environment: tx?.environment ?? notification.data?.environment ?? null,
    p_user: token,
    p_revoked_at: tx?.revocationDate
      ? new Date(tx.revocationDate).toISOString()
      : null,
  });
  if (error) return fail(500, "internal_error");
  return json(200, { status: data ?? "unknown" });
});
