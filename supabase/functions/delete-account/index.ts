// POST /functions/v1/delete-account
// Deletes the caller's Supabase Auth user. FKs cascade profile, friendships,
// requests, invitations and sessions; duels keep the opponent's history with
// the deleted side nulled. Migrated Firebase data is purged and tombstoned so it
// cannot be re-claimed later.
import { requireUser } from "../_shared/auth.ts";
import { dbErrorCode, fail, json } from "../_shared/http.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return fail(405, "method_not_allowed");
  const auth = await requireUser(req);
  if (auth instanceof Response) return auth;
  const callerId = auth.userId;
  const admin = auth.admin;

  const rate = await admin.rpc("edge_check_rate", {
    p_user: callerId,
    p_action: "delete_account",
    p_max: 5,
    p_window_seconds: 3600,
  });
  if (rate.error) {
    return fail(
      dbErrorCode(rate.error) === "rate_limited" ? 429 : 500,
      dbErrorCode(rate.error),
    );
  }

  const purge = await admin.rpc("purge_account_data", { p_user: callerId });
  if (purge.error) {
    console.error("purge_account_data failed", {
      code: dbErrorCode(purge.error),
    });
    return fail(500, "delete_failed");
  }
  const del = await admin.auth.admin.deleteUser(callerId);
  if (del.error) {
    console.error("deleteUser failed", { status: del.error.status });
    return fail(500, "delete_failed");
  }
  return json(200, { status: "deleted" });
});
