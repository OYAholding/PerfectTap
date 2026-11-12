// POST /functions/v1/claim-legacy-account
// Body: { firebaseIdToken: string, password?: string }
//
// Moves a Firebase-era player (progress, verified scores, friendships) onto the
// calling Supabase user. The Firebase ID token proves ownership of the legacy
// account. The email login is carried over ONLY if Firebase had verified that
// the player owns the address (email_verified); otherwise the player links and
// verifies an email again in the app (Supabase email-change OTP).
import { withSupabase } from "@supabase/server";
import { dbErrorCode, fail, json, readJson } from "../_shared/http.ts";
import { verifyFirebaseIdToken, verifyFirebasePassword } from "../_shared/firebase.ts";

type ClaimResult = { status: string; user_id?: string; username_conflict?: boolean; friendships_restored?: number };

export default {
  fetch: withSupabase({ auth: "user" }, async (req, ctx) => {
    const callerId = ctx.userClaims?.id;
    if (!callerId) return fail(401, "not_authenticated");
    const admin = ctx.supabaseAdmin;

    const body = await readJson(req);
    if (!body || typeof body.firebaseIdToken !== "string") return fail(400, "invalid_payload");
    const password = typeof body.password === "string" ? body.password : null;

    const rate = await admin.rpc("edge_check_rate", {
      p_user: callerId, p_action: "legacy_claim", p_max: 10, p_window_seconds: 3600,
    });
    if (rate.error) return fail(dbErrorCode(rate.error) === "rate_limited" ? 429 : 500, dbErrorCode(rate.error));

    const fb = await verifyFirebaseIdToken(body.firebaseIdToken);
    if (!fb) return fail(401, "invalid_firebase_token");

    let passwordVerified = false;
    if (password !== null) {
      if (!fb.email || !(await verifyFirebasePassword(fb.uid, fb.email, password))) {
        return fail(401, "invalid_credentials");
      }
      passwordVerified = true;
    }

    const claim = await admin.rpc("claim_legacy_profile", { p_user: callerId, p_firebase_uid: fb.uid });
    if (claim.error) {
      console.error("claim_legacy_profile failed", { code: dbErrorCode(claim.error) });
      return fail(500, "claim_failed");
    }
    const result = claim.data as ClaimResult;

    // Account with this Firebase identity already lives on another Supabase user.
    if (result.status === "claimed_elsewhere") {
      if (!passwordVerified || !fb.email || !fb.emailVerified || !result.user_id) {
        return json(409, { status: "claimed_elsewhere" });
      }
      const upd = await admin.auth.admin.updateUserById(result.user_id, {
        email: fb.email, email_confirm: true, password: password!,
      });
      if (upd.error) return fail(500, "account_update_failed");
      return json(200, { status: "sign_in_required", email: fb.email });
    }
    if (result.status === "user_has_profile" || result.status === "user_already_linked") {
      return json(409, { status: result.status });
    }

    // claimed | no_legacy_data | already_claimed → carry the email login over.
    let emailLinked = false;
    if (fb.email && fb.emailVerified) {
      const { data: current } = await admin.auth.admin.getUserById(callerId);
      const callerEmail = current?.user?.email ?? null;
      const inUse = await admin.rpc("edge_email_in_use", { p_email: fb.email, p_except: callerId });
      if (!inUse.error && inUse.data !== true && (!callerEmail || callerEmail === fb.email)) {
        const upd = await admin.auth.admin.updateUserById(callerId, {
          email: fb.email, email_confirm: true, ...(passwordVerified ? { password: password! } : {}),
        });
        emailLinked = !upd.error;
      }
    }

    return json(200, {
      status: result.status,
      usernameConflict: result.username_conflict ?? false,
      friendshipsRestored: result.friendships_restored ?? 0,
      emailLinked,
      passwordSet: emailLinked && passwordVerified,
    });
  }),
};
