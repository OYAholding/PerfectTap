/**
 * Native Ad Bridge — communicates with native iOS/Android code via postMessage.
 *
 * Native side must:
 * 1. Listen for messages from the webview with type "REQUEST_REWARDED_AD"
 * 2. Show the rewarded ad (AdMob, etc.)
 * 3. Post a message back to the webview with type "REWARDED_AD_RESULT" and { success: boolean }
 *
 * When no native bridge is detected (dev/browser), falls back to a simulated ad.
 *
 * iOS (WKWebView):  window.webkit.messageHandlers.adBridge.postMessage(...)
 * Android (WebView): window.AndroidAdBridge.requestRewardedAd(...)
 */

const TIMEOUT_MS = 30000; // 30s timeout for native response

let _pendingResolve = null;

/**
 * Returns true if running inside a native iOS or Android webview with the ad bridge installed.
 */
export function isNativeBridgeAvailable() {
  return !!(
    window.webkit?.messageHandlers?.adBridge ||
    window.AndroidAdBridge?.requestRewardedAd
  );
}

/**
 * Request a rewarded ad from the native layer.
 * Returns Promise<{ success: boolean }>
 */
export function requestRewardedAd() {
  // Clean up any previous pending request
  if (_pendingResolve) {
    _pendingResolve({ success: false });
    _pendingResolve = null;
  }

  // --- Native iOS bridge ---
  if (window.webkit?.messageHandlers?.adBridge) {
    return new Promise((resolve) => {
      _pendingResolve = resolve;

      const timeout = setTimeout(() => {
        if (_pendingResolve === resolve) {
          _pendingResolve = null;
          resolve({ success: false });
        }
      }, TIMEOUT_MS);

      // Store timeout ref so native callback can clear it
      _pendingResolve._timeout = timeout;

      window.webkit.messageHandlers.adBridge.postMessage({
        type: "REQUEST_REWARDED_AD",
      });
    });
  }

  // --- Native Android bridge ---
  if (window.AndroidAdBridge?.requestRewardedAd) {
    return new Promise((resolve) => {
      _pendingResolve = resolve;

      const timeout = setTimeout(() => {
        if (_pendingResolve === resolve) {
          _pendingResolve = null;
          resolve({ success: false });
        }
      }, TIMEOUT_MS);

      _pendingResolve._timeout = timeout;

      window.AndroidAdBridge.requestRewardedAd();
    });
  }

  // --- Fallback: simulate ad in dev/browser ---
  return new Promise((resolve) => {
    console.log("[AdBridge] No native bridge detected — simulating rewarded ad (dev mode)");
    setTimeout(() => {
      resolve({ success: true });
    }, 2000);
  });
}

/**
 * Called by native code to deliver the ad result.
 * Native iOS should call: window.onRewardedAdResult({ success: true/false })
 * Native Android should call: window.onRewardedAdResult({ success: true/false })
 */
window.onRewardedAdResult = function (result) {
  if (_pendingResolve) {
    if (_pendingResolve._timeout) clearTimeout(_pendingResolve._timeout);
    const resolve = _pendingResolve;
    _pendingResolve = null;
    resolve({ success: !!result?.success });
  }
};