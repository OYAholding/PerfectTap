// Apple signature verification (App Store Server Library). Configuration comes
// from Edge Function secrets — nothing is hard-coded:
//   APPLE_ROOT_CAS_B64   comma-separated base64 DER root certificates from
//                        https://www.apple.com/certificateauthority/ (Apple Root CA G3 …)
//   APPLE_ENVIRONMENT    Production | Sandbox (default Sandbox)
//   APPLE_APP_APPLE_ID   numeric App Store app id (required for Production)
import { Environment, SignedDataVerifier } from "@apple/app-store-server-library";
import { Buffer } from "node:buffer";
import { BUNDLE_ID } from "./purchases.ts";

export function makeVerifier(): SignedDataVerifier | null {
  const roots = (Deno.env.get("APPLE_ROOT_CAS_B64") ?? "").split(",").map((s) => s.trim()).filter(Boolean);
  if (roots.length === 0) return null;
  const env = Deno.env.get("APPLE_ENVIRONMENT") === "Production" ? Environment.PRODUCTION : Environment.SANDBOX;
  const appAppleId = Number(Deno.env.get("APPLE_APP_APPLE_ID") ?? "") || undefined;
  if (env === Environment.PRODUCTION && !appAppleId) return null;
  return new SignedDataVerifier(roots.map((b64) => Buffer.from(b64, "base64")), true, env, BUNDLE_ID, appAppleId);
}
