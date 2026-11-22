// Pure purchase logic shared by verify-purchase and app-store-notifications.
// No network / Apple library imports here, so it is unit-tested with fakes
// (purchases.test.ts).

/** Fields we use from a decoded JWSTransactionDecodedPayload. */
export interface DecodedTransaction {
  transactionId?: string;
  originalTransactionId?: string;
  productId?: string;
  bundleId?: string;
  environment?: string;
  appAccountToken?: string;
  purchaseDate?: number;
  revocationDate?: number;
}

export type RecordRpc = (args: {
  p_user: string;
  p_transaction_id: string;
  p_original_transaction_id: string;
  p_product_id: string;
  p_environment: string;
  p_purchased_at: string;
  p_revoked_at: string | null;
}) => PromiseLike<{ data: string | null; error: { message?: string } | null }>;

export type Outcome =
  | { status: 200; body: { status: string } }
  | { status: 400 | 403 | 409 | 500; body: { error: string } };

export const BUNDLE_ID = "com.perfecttap.app";
const ENVIRONMENTS = new Set(["Production", "Sandbox", "Xcode", "LocalTesting"]);

/**
 * Records a transaction that Apple's signature check has already verified.
 * - must be for this app
 * - if it carries an appAccountToken it must be the caller (stops one player
 *   replaying another player's receipt)
 * - the ledger insert is idempotent (unique transaction id)
 */
export async function recordVerifiedTransaction(
  tx: DecodedTransaction,
  callerId: string,
  record: RecordRpc,
): Promise<Outcome> {
  if (!tx.transactionId || !tx.productId) return { status: 400, body: { error: "invalid_transaction" } };
  if (tx.bundleId !== BUNDLE_ID) return { status: 403, body: { error: "wrong_bundle" } };
  if (!tx.environment || !ENVIRONMENTS.has(tx.environment)) return { status: 400, body: { error: "invalid_environment" } };
  if (tx.appAccountToken && tx.appAccountToken.toLowerCase() !== callerId.toLowerCase()) {
    return { status: 403, body: { error: "account_mismatch" } };
  }
  const { data, error } = await record({
    p_user: callerId,
    p_transaction_id: tx.transactionId,
    p_original_transaction_id: tx.originalTransactionId ?? tx.transactionId,
    p_product_id: tx.productId,
    p_environment: tx.environment,
    p_purchased_at: new Date(tx.purchaseDate ?? Date.now()).toISOString(),
    p_revoked_at: tx.revocationDate ? new Date(tx.revocationDate).toISOString() : null,
  });
  if (error) {
    const code = error.message && /^[a-z_]{3,40}$/.test(error.message) ? error.message : "internal_error";
    const status = code === "unknown_product" ? 400 : code === "owned_by_other_account" ? 409 : 500;
    return { status, body: { error: code } };
  }
  return { status: 200, body: { status: data ?? "unknown" } };
}

/** App Store Server Notifications V2 types that take an entitlement away. */
export const REVOKING_NOTIFICATIONS = new Set(["REFUND", "REVOKE"]);
