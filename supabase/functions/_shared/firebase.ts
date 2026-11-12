// Verifies Firebase Auth ID tokens and (optionally) Firebase email/password
// credentials, so legacy players can move their data to Supabase.
// Uses only Google's public endpoints — no Firebase service account needed.
import { createRemoteJWKSet, jwtVerify } from "jose";

const PROJECT_ID = Deno.env.get("FIREBASE_PROJECT_ID") ?? "perfecttap-48a08";
// Overridable for local integration tests only.
const JWKS_URL = Deno.env.get("FIREBASE_JWKS_URL") ??
  "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";
const IDENTITY_URL = Deno.env.get("FIREBASE_IDENTITY_URL") ?? "https://identitytoolkit.googleapis.com";
const WEB_API_KEY = Deno.env.get("FIREBASE_WEB_API_KEY") ?? "";

const jwks = createRemoteJWKSet(new URL(JWKS_URL));

export interface FirebaseIdentity {
  uid: string;
  email: string | null;
  provider: string | null;
}

export async function verifyFirebaseIdToken(token: string): Promise<FirebaseIdentity | null> {
  if (typeof token !== "string" || token.length > 4096) return null;
  try {
    const { payload } = await jwtVerify(token, jwks, {
      issuer: `https://securetoken.google.com/${PROJECT_ID}`,
      audience: PROJECT_ID,
      algorithms: ["RS256"],
      clockTolerance: 30,
    });
    const now = Math.floor(Date.now() / 1000);
    if (typeof payload.sub !== "string" || payload.sub.length === 0 || payload.sub.length > 128) return null;
    if (typeof payload.auth_time !== "number" || payload.auth_time > now + 30) return null;
    const firebase = payload.firebase as { sign_in_provider?: string } | undefined;
    return {
      uid: payload.sub,
      email: typeof payload.email === "string" ? payload.email.toLowerCase() : null,
      provider: firebase?.sign_in_provider ?? null,
    };
  } catch {
    return null;
  }
}

/** True only if Firebase accepts these credentials for exactly `uid`. */
export async function verifyFirebasePassword(uid: string, email: string, password: string): Promise<boolean> {
  if (!WEB_API_KEY || password.length < 6 || password.length > 128) return false;
  try {
    const res = await fetch(
      `${IDENTITY_URL}/v1/accounts:signInWithPassword?key=${encodeURIComponent(WEB_API_KEY)}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, password, returnSecureToken: false }),
      },
    );
    if (!res.ok) return false;
    const body = await res.json() as { localId?: string };
    return body.localId === uid;
  } catch {
    return false;
  }
}
