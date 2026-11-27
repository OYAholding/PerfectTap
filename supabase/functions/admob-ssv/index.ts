// GET /functions/v1/admob-ssv   (AdMob rewarded-ad server-side verification)
// Google calls this URL (AdMob > ad unit > Server-side verification). No user
// JWT: authenticity comes from Google's ECDSA signature over the query string,
// verified with the published verifier keys (cached). A verified callback is
// recorded with the service role via record_verified_rewarded_claim, which
// computes the grant from the active economy config (the callback's
// reward_amount is ignored). Terminal outcomes answer 200 so Google stops
// retrying; transient failures answer 5xx so Google retries.
import { serviceClient } from "../_shared/auth.ts";
import {
  handleAdMobCallback,
  makeGoogleKeyLookup,
  parseAllowedAdUnits,
} from "../_shared/admob.ts";

const lookup = makeGoogleKeyLookup();
const allowedAdUnits = parseAllowedAdUnits(
  Deno.env.get("ADMOB_ALLOWED_AD_UNITS"),
);

Deno.serve((req) =>
  handleAdMobCallback(req, {
    lookup,
    allowedAdUnits,
    claim: () => {
      const admin = serviceClient();
      if (admin instanceof Response) return null;
      return (args) => admin.rpc("record_verified_rewarded_claim", args);
    },
  })
);
