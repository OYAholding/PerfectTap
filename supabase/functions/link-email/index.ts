// POST /functions/v1/link-email   Body: { email, password }
//
// "Cloud Backup": turns the caller's anonymous account into an email/password
// account (same user id, so no data moves). Done server-side because the Free
// plan's built-in SMTP cannot send verification mail to arbitrary players.
// Same trust level as the Firebase build (which never verified emails either).
import { withSupabase } from "@supabase/server";
import { dbErrorCode, EMAIL_RE, fail, json, readJson } from "../_shared/http.ts";

export default {
  fetch: withSupabase({ auth: "user" }, async (req, ctx) => {
    const callerId = ctx.userClaims?.id;
    if (!callerId) return fail(401, "not_authenticated");
    const admin = ctx.supabaseAdmin;

    const body = await readJson(req);
    const email = typeof body?.email === "string" ? body.email.trim().toLowerCase() : "";
    const password = typeof body?.password === "string" ? body.password : "";
    if (!EMAIL_RE.test(email) || email.length > 254) return fail(400, "invalid_email");
    if (password.length < 6 || password.length > 128) return fail(400, "weak_password");

    const rate = await admin.rpc("edge_check_rate", {
      p_user: callerId, p_action: "link_email", p_max: 5, p_window_seconds: 3600,
    });
    if (rate.error) return fail(dbErrorCode(rate.error) === "rate_limited" ? 429 : 500, dbErrorCode(rate.error));

    const { data: current, error: getErr } = await admin.auth.admin.getUserById(callerId);
    if (getErr || !current?.user) return fail(401, "not_authenticated");
    if (current.user.email) return json(200, { status: "already_linked", email: current.user.email });

    const inUse = await admin.rpc("edge_email_in_use", { p_email: email, p_except: callerId });
    if (inUse.error) return fail(500, "link_failed");
    if (inUse.data === true) return fail(409, "email_in_use");

    const upd = await admin.auth.admin.updateUserById(callerId, { email, password, email_confirm: true });
    if (upd.error) {
      const msg = (upd.error.message ?? "").toLowerCase();
      if (msg.includes("already") || (upd.error as { code?: string }).code === "email_exists") {
        return fail(409, "email_in_use");
      }
      console.error("link-email update failed", { status: upd.error.status });
      return fail(500, "link_failed");
    }
    return json(200, { status: "linked", email });
  }),
};
