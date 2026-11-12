// POST /functions/v1/delete-account
// Deletes the caller's Supabase Auth user. FKs cascade profile, friendships,
// requests, invitations and sessions; duels keep the opponent's history with
// the deleted side nulled. Migrated Firebase data is purged and tombstoned so it
// cannot be re-claimed later.
import { withSupabase } from "@supabase/server";
import { dbErrorCode, fail, json } from "../_shared/http.ts";

export default {
  fetch: withSupabase({ auth: "user" }, async (req, ctx) => {
    if (req.method !== "POST") return fail(405, "method_not_allowed");
    const callerId = ctx.userClaims?.id;
    if (!callerId) return fail(401, "not_authenticated");
    const admin = ctx.supabaseAdmin;

    const rate = await admin.rpc("edge_check_rate", {
      p_user: callerId, p_action: "delete_account", p_max: 5, p_window_seconds: 3600,
    });
    if (rate.error) return fail(dbErrorCode(rate.error) === "rate_limited" ? 429 : 500, dbErrorCode(rate.error));

    const purge = await admin.rpc("purge_account_data", { p_user: callerId });
    if (purge.error) {
      console.error("purge_account_data failed", { code: dbErrorCode(purge.error) });
      return fail(500, "delete_failed");
    }
    const del = await admin.auth.admin.deleteUser(callerId);
    if (del.error) {
      console.error("deleteUser failed", { status: del.error.status });
      return fail(500, "delete_failed");
    }
    return json(200, { status: "deleted" });
  }),
};
