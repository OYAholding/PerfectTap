import { useState, useRef, useCallback } from "react";

/**
 * Native-style pull-to-refresh hook.
 * Returns { pullProps, indicatorEl, refreshing }
 * Spread pullProps onto the scrollable container div.
 */
export default function usePullToRefresh(onRefresh) {
  const [pulling, setPulling] = useState(false);
  const [pullDistance, setPullDistance] = useState(0);
  const [refreshing, setRefreshing] = useState(false);
  const startY = useRef(0);
  const isPulling = useRef(false);

  const THRESHOLD = 80;

  const onTouchStart = useCallback((e) => {
    // Only allow pull when scrolled to top
    const el = e.currentTarget;
    if (el.scrollTop > 0) return;
    startY.current = e.touches[0].clientY;
    isPulling.current = true;
  }, []);

  const onTouchMove = useCallback((e) => {
    if (!isPulling.current) return;
    const diff = e.touches[0].clientY - startY.current;
    if (diff < 0) {
      isPulling.current = false;
      setPulling(false);
      setPullDistance(0);
      return;
    }
    // Dampen the pull distance
    const dampened = Math.min(diff * 0.5, 120);
    setPullDistance(dampened);
    setPulling(true);
  }, []);

  const onTouchEnd = useCallback(async () => {
    if (!isPulling.current && !pulling) return;
    isPulling.current = false;

    if (pullDistance >= THRESHOLD && onRefresh) {
      setRefreshing(true);
      setPullDistance(THRESHOLD * 0.5);
      await onRefresh();
      setRefreshing(false);
    }

    setPulling(false);
    setPullDistance(0);
  }, [pullDistance, pulling, onRefresh]);

  const pullProps = {
    onTouchStart,
    onTouchMove,
    onTouchEnd,
  };

  const progress = Math.min(pullDistance / THRESHOLD, 1);

  const indicatorEl = (pulling || refreshing) ? (
    <div
      className="flex justify-center overflow-hidden transition-all duration-150"
      style={{ height: pulling ? pullDistance : refreshing ? 40 : 0 }}
    >
      <div className="flex items-center justify-center py-2">
        <div
          className={`w-6 h-6 border-2 border-violet-400 border-t-transparent rounded-full ${
            refreshing ? "animate-spin" : ""
          }`}
          style={!refreshing ? { transform: `rotate(${progress * 360}deg)` } : undefined}
        />
      </div>
    </div>
  ) : null;

  return { pullProps, indicatorEl, refreshing };
}