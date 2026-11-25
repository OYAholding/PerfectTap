import { createClient } from "npm:@supabase/supabase-js@2.119.0";
import { fail } from "./http.ts";

/**
 * Authenticates the caller with Supabase Auth and returns a server-only client.
 * The service key never leaves the Edge Function. Missing, malformed, expired,
 * or revoked bearer tokens all fail closed.
 */
export async function requireUser(
  req: Request,
) {
  const authorization = req.headers.get("authorization") ?? "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match) return fail(401, "not_authenticated");

  const url = Deno.env.get("SUPABASE_URL");
  const secret = Deno.env.get("SUPABASE_SECRET_KEY") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !secret) return fail(503, "server_not_configured");

  const admin = createClient(url, secret, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await admin.auth.getUser(match[1]);
  const userId = data.user?.id;
  if (error || !userId) return fail(401, "not_authenticated");
  return { userId, admin };
}
