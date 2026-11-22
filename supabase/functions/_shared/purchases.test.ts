import { assertEquals } from "jsr:@std/assert@1.0.13";
import { type DecodedTransaction, recordVerifiedTransaction, type RecordRpc } from "./purchases.ts";

const caller = "aaaaaaaa-0000-0000-0000-000000000001";
const base: DecodedTransaction = {
  transactionId: "2000000001",
  originalTransactionId: "2000000001",
  productId: "com.perfecttap.skin.glitchmode",
  bundleId: "com.perfecttap.app",
  environment: "Sandbox",
  appAccountToken: caller.toUpperCase(),
  purchaseDate: 1_790_000_000_000,
};

function fakeRpc(reply: { data: string | null; error: { message?: string } | null }) {
  const calls: unknown[] = [];
  const rpc: RecordRpc = (args) => { calls.push(args); return Promise.resolve(reply); };
  return { rpc, calls };
}

Deno.test("records a verified transaction for the caller", async () => {
  const { rpc, calls } = fakeRpc({ data: "granted", error: null });
  const out = await recordVerifiedTransaction(base, caller, rpc);
  assertEquals(out, { status: 200, body: { status: "granted" } });
  assertEquals(calls.length, 1);
});

Deno.test("rejects another app's transaction", async () => {
  const { rpc, calls } = fakeRpc({ data: "granted", error: null });
  const out = await recordVerifiedTransaction({ ...base, bundleId: "com.other.app" }, caller, rpc);
  assertEquals(out.status, 403);
  assertEquals(calls.length, 0);
});

Deno.test("rejects a receipt bound to a different player", async () => {
  const { rpc, calls } = fakeRpc({ data: "granted", error: null });
  const out = await recordVerifiedTransaction({ ...base, appAccountToken: "bbbbbbbb-0000-0000-0000-000000000009" }, caller, rpc);
  assertEquals(out, { status: 403, body: { error: "account_mismatch" } });
  assertEquals(calls.length, 0);
});

Deno.test("passes revocation through and maps unknown products", async () => {
  const { rpc, calls } = fakeRpc({ data: null, error: { message: "unknown_product" } });
  const out = await recordVerifiedTransaction({ ...base, revocationDate: 1_790_000_100_000 }, caller, rpc);
  assertEquals(out, { status: 400, body: { error: "unknown_product" } });
  assertEquals((calls[0] as { p_revoked_at: string }).p_revoked_at, new Date(1_790_000_100_000).toISOString());
});

Deno.test("never leaks raw database errors", async () => {
  const { rpc } = fakeRpc({ data: null, error: { message: "relation \"x\" does not exist" } });
  const out = await recordVerifiedTransaction(base, caller, rpc);
  assertEquals(out, { status: 500, body: { error: "internal_error" } });
});
