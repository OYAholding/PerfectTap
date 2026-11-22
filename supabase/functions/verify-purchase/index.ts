// POST /functions/v1/verify-purchase   { signedTransaction: <StoreKit 2 JWS> }
// Called by the app (PurchaseManager) before it finishes a transaction.
// Verifies the JWS with Apple's certificate chain, then records it in
// private.purchase_ledger (idempotent). Replies:
//   200 { status: "granted" | "already_granted" | "revoked" | "already_revoked" }
//   4xx { error } → the app never grants;  5xx / network → the app retries later.
import { withSupabase } from "@supabase/server";
import { dbErrorCode, fail, json, readJson } from "../_shared/http.ts";
import { makeVerifier } from "../_shared/apple.ts";
import { recordVerifiedTransaction } from "../_shared/purchases.ts";

export default {
  fetch: withSupabase({ auth: "user" }, async (req, ctx) => {
    const callerId = ctx.userClaims?.id;
    if (!callerId) return fail(401, "not_authenticated");
    const body = await readJson(req);
    const jws = typeof body?.signedTransaction === "string" ? body.signedTransaction : "";
    if (!jws || jws.length > 16_000) return fail(400, "invalid_payload");

    const admin = ctx.supabaseAdmin;
    const rate = await admin.rpc("edge_check_rate", {
      p_user: callerId, p_action: "verify_purchase", p_max: 30, p_window_seconds: 3600,
    });
    if (rate.error) return fail(dbErrorCode(rate.error) === "rate_limited" ? 429 : 500, dbErrorCode(rate.error));

    const verifier = makeVerifier();
    if (!verifier) return fail(503, "verification_not_configured");
    let tx;
    try {
      tx = await verifier.verifyAndDecodeTransaction(jws);
    } catch {
      return fail(400, "invalid_signature");
    }
    const out = await recordVerifiedTransaction(tx, callerId, (args) => admin.rpc("record_verified_purchase", args));
    return json(out.status, out.body);
  }),
};
