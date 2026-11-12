// Shared helpers for PerfectTap Edge Functions.
// Responses carry stable machine codes only — never stack traces or secrets.

export function json(status: number, body: Record<string, unknown>): Response {
  return Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
}

export function fail(status: number, code: string): Response {
  return json(status, { error: code });
}

export async function readJson(req: Request, maxBytes = 16_384): Promise<Record<string, unknown> | null> {
  if (req.method !== "POST") return null;
  const text = await req.text();
  if (text.length > maxBytes) return null;
  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

/** Maps a Postgres RAISE from private.fail() to its code (e.g. "rate_limited"). */
export function dbErrorCode(error: { message?: string } | null): string {
  return error?.message && /^[a-z_]{3,40}$/.test(error.message) ? error.message : "internal_error";
}

export const EMAIL_RE = /^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{2,24}$/;
