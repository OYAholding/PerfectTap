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
const ENVIRONMENTS = new Set([
  "Production",
  "Sandbox",
  "Xcode",
  "LocalTesting",
]);
const RESTORABLE_NON_CONSUMABLES = new Set([
  "com.perfecttap.removeads",
  "com.perfecttap.skin.neonpulse",
  "com.perfecttap.skin.liquidchrome",
  "com.perfecttap.skin.glitchmode",
  "com.perfecttap.skin.cosmicgold",
]);

export function isRestorableNonConsumable(productId?: string): boolean {
  return productId !== undefined && RESTORABLE_NON_CONSUMABLES.has(productId);
}

/**
 * Records a transaction that Apple's signature check has already verified.
 * - must be for this app
 * - consumables require appAccountToken == caller (stops replay to another
 *   balance); non-consumables may restore locally when Apple returns the signed
 *   transaction to a different anonymous installation after reinstall
 * - the ledger insert is idempotent (unique transaction id)
 */
export async function recordVerifiedTransaction(
  tx: DecodedTransaction,
  callerId: string,
  record: RecordRpc,
): Promise<Outcome> {
  if (!tx.transactionId || !tx.productId) {
    return { status: 400, body: { error: "invalid_transaction" } };
  }
  if (tx.bundleId !== BUNDLE_ID) {
    return { status: 403, body: { error: "wrong_bundle" } };
  }
  if (!tx.environment || !ENVIRONMENTS.has(tx.environment)) {
    return { status: 400, body: { error: "invalid_environment" } };
  }
  const localRestore = isRestorableNonConsumable(tx.productId) &&
    (!tx.appAccountToken ||
      tx.appAccountToken.toLowerCase() !== callerId.toLowerCase());
  if (localRestore) {
    // Do not move or duplicate the server-owned ledger grant. The app may honor
    // this only while processing StoreKit's locally verified Transaction.
    return { status: 200, body: { status: "verified_local_restore" } };
  }
  if (!tx.appAccountToken) {
    return { status: 403, body: { error: "missing_account_token" } };
  }
  if (tx.appAccountToken.toLowerCase() !== callerId.toLowerCase()) {
    return { status: 403, body: { error: "account_mismatch" } };
  }
  const { data, error } = await record({
    p_user: callerId,
    p_transaction_id: tx.transactionId,
    p_original_transaction_id: tx.originalTransactionId ?? tx.transactionId,
    p_product_id: tx.productId,
    p_environment: tx.environment,
    p_purchased_at: new Date(tx.purchaseDate ?? Date.now()).toISOString(),
    p_revoked_at: tx.revocationDate
      ? new Date(tx.revocationDate).toISOString()
      : null,
  });
  if (error) {
    const code = error.message && /^[a-z_]{3,40}$/.test(error.message)
      ? error.message
      : "internal_error";
    if (code === "owned_by_other_account" &&
      isRestorableNonConsumable(tx.productId)) {
      return { status: 200, body: { status: "verified_local_restore" } };
    }
    const status = code === "unknown_product" || code === "disabled_product"
      ? 400
      : code === "owned_by_other_account"
      ? 409
      : 500;
    return { status, body: { error: code } };
  }
  return { status: 200, body: { status: data ?? "unknown" } };
}

/** App Store Server Notifications V2 types that take an entitlement away. */
export const REVOKING_NOTIFICATIONS = new Set(["REFUND", "REVOKE"]);
export const REINSTATING_NOTIFICATIONS = new Set(["REFUND_REVERSED"]);
