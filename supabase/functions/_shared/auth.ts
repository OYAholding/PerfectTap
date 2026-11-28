import {
  createClient,
  type SupabaseClient,
} from "npm:@supabase/supabase-js@2.119.0";
import { fail } from "./http.ts";

/**
 * Server-only Supabase client with the service key (never leaves the Edge
 * Function). Returns a 503 Response when the function is not configured.
 */
export function serviceClient(): SupabaseClient | Response {
  const url = Deno.env.get("SUPABASE_URL");
  const secret = Deno.env.get("SUPABASE_SECRET_KEY") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !secret) return fail(503, "server_not_configured");
  return createClient(url, secret, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/**
 * Authenticates the caller with Supabase Auth and returns a server-only client.
 * Missing, malformed, expired, or revoked bearer tokens all fail closed.
 */
export async function requireUser(
  req: Request,
) {
  const authorization = req.headers.get("authorization") ?? "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match) return fail(401, "not_authenticated");

  const admin = serviceClient();
  if (admin instanceof Response) return admin;
  const { data, error } = await admin.auth.getUser(match[1]);
  const userId = data.user?.id;
  if (error || !userId) return fail(401, "not_authenticated");
  return { userId, admin };
}
