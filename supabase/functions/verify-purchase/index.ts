// POST /functions/v1/verify-purchase   { signedTransaction: <StoreKit 2 JWS> }
// Called by the app (PurchaseManager) before it finishes a transaction.
// Verifies the JWS with Apple's certificate chain, then records it in
// private.purchase_ledger (idempotent). Replies:
//   200 { status: "granted" | "already_granted" | "revoked" | "already_revoked" }
//   4xx { error } → the app never grants;  5xx / network → the app retries later.
import { requireUser } from "../_shared/auth.ts";
import { dbErrorCode, fail, json, readJson } from "../_shared/http.ts";
import { makeVerifierSet } from "../_shared/apple.ts";
import { recordVerifiedTransaction } from "../_shared/purchases.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return fail(405, "method_not_allowed");
  const auth = await requireUser(req);
  if (auth instanceof Response) return auth;
  const callerId = auth.userId;
  const body = await readJson(req);
  const jws = typeof body?.signedTransaction === "string"
    ? body.signedTransaction
    : "";
  if (!jws || jws.length > 16_000) return fail(400, "invalid_payload");

  const admin = auth.admin;
  const rate = await admin.rpc("edge_check_rate", {
    p_user: callerId,
    p_action: "verify_purchase",
    p_max: 30,
    p_window_seconds: 3600,
  });
  if (rate.error) {
    return fail(
      dbErrorCode(rate.error) === "rate_limited" ? 429 : 500,
      dbErrorCode(rate.error),
    );
  }

  const verifier = makeVerifierSet();
  if (!verifier) return fail(503, "verification_not_configured");
  let tx;
  try {
    tx = await verifier.verifyAndDecodeTransaction(jws);
  } catch {
    return fail(400, "invalid_signature");
  }
  const out = await recordVerifiedTransaction(
    tx,
    callerId,
    (args) => admin.rpc("record_verified_purchase", args),
  );
  return json(out.status, out.body);
});
