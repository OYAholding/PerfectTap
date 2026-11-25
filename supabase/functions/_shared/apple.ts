// Apple signature verification (App Store Server Library). Configuration comes
// from Edge Function secrets — nothing is hard-coded:
//   APPLE_ROOT_CAS_B64   comma-separated base64 DER root certificates from
//                        https://www.apple.com/certificateauthority/ (Apple Root CA G3 …)
//   APPLE_ENABLED_ENVIRONMENTS comma-separated Production,Sandbox (no default)
//   APPLE_APP_APPLE_ID   numeric App Store app id (required for Production)
import {
  Environment,
  SignedDataVerifier,
} from "@apple/app-store-server-library";
import { Buffer } from "node:buffer";
import { BUNDLE_ID } from "./purchases.ts";

type DecodedTransaction = Awaited<
  ReturnType<SignedDataVerifier["verifyAndDecodeTransaction"]>
>;
type DecodedNotification = Awaited<
  ReturnType<SignedDataVerifier["verifyAndDecodeNotification"]>
>;

export interface AppleVerifierSet {
  verifyAndDecodeTransaction(jws: string): Promise<DecodedTransaction>;
  verifyAndDecodeNotification(jws: string): Promise<DecodedNotification>;
}

export function makeVerifierSet(): AppleVerifierSet | null {
  const roots = (Deno.env.get("APPLE_ROOT_CAS_B64") ?? "").split(",").map((s) =>
    s.trim()
  ).filter(Boolean);
  if (roots.length === 0) return null;
  const appAppleId = Number(Deno.env.get("APPLE_APP_APPLE_ID") ?? "") ||
    undefined;
  const configured = new Set(
    (Deno.env.get("APPLE_ENABLED_ENVIRONMENTS") ?? "").split(",").map((s) =>
      s.trim()
    ),
  );
  const environments: Environment[] = [];
  if (configured.has("Production")) environments.push(Environment.PRODUCTION);
  if (configured.has("Sandbox")) environments.push(Environment.SANDBOX);
  if (
    environments.length === 0 ||
    (environments.includes(Environment.PRODUCTION) && !appAppleId)
  ) return null;
  const rootBuffers = roots.map((b64) => Buffer.from(b64, "base64"));
  const verifiers = environments.map((environment) =>
    new SignedDataVerifier(
      rootBuffers,
      true,
      environment,
      BUNDLE_ID,
      environment === Environment.PRODUCTION ? appAppleId : undefined,
    )
  );

  async function tryEvery<T>(
    operation: (verifier: SignedDataVerifier) => Promise<T>,
  ): Promise<T> {
    let lastError: unknown = new Error("no_verifier");
    for (const verifier of verifiers) {
      try {
        return await operation(verifier);
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError;
  }

  return {
    verifyAndDecodeTransaction: (jws) =>
      tryEvery((verifier) => verifier.verifyAndDecodeTransaction(jws)),
    verifyAndDecodeNotification: (jws) =>
      tryEvery((verifier) => verifier.verifyAndDecodeNotification(jws)),
  };
}
