import React, { useRef, useEffect, useImperativeHandle, forwardRef } from "react";

const TapBar = forwardRef(function TapBar({ indicatorPos, theme }, ref) {
  const indicatorRef = useRef(null);

  // Expose imperative setPosition for direct DOM updates (no React re-render)
  useImperativeHandle(ref, () => ({
    setPosition(pos) {
      if (indicatorRef.current) {
        indicatorRef.current.style.left = pos + "%";
      }
    }
  }));

  // Also support prop-based updates as fallback
  useEffect(() => {
    if (indicatorRef.current && indicatorPos !== undefined) {
      indicatorRef.current.style.left = indicatorPos + "%";
    }
  }, [indicatorPos]);

  return (
    <div className="w-full">
      {/* Labels */}
      <div className="flex justify-between text-white/20 text-xs mb-2 px-1">
        <span>◀</span>
        <span className="tracking-widest">AIM FOR CENTER</span>
        <span>▶</span>
      </div>

      {/* Bar */}
      <div className="relative w-full h-12 bg-white/5 border border-white/10 rounded-2xl overflow-hidden">
        {/* Zone backgrounds */}
        <div
          className="absolute top-0 h-full bg-yellow-500/10"
          style={{ left: "30%", width: "40%" }}
        />
        <div
          className="absolute top-0 h-full bg-green-500/15"
          style={{ left: "40%", width: "20%" }}
        />
        <div
          className="absolute top-0 h-full bg-violet-500/25"
          style={{ left: "46%", width: "8%" }}
        />

        {/* Center target line */}
        <div className="absolute top-0 h-full w-0.5 bg-white/30 left-1/2 -translate-x-1/2" />
        <div className="absolute -top-1 left-1/2 -translate-x-1/2 w-3 h-3 rotate-45 bg-white/40" />

        {/* Moving indicator — positioned via ref, NOT React state */}
        <div
          ref={indicatorRef}
          className="absolute top-1/2 -translate-y-1/2 -translate-x-1/2 pointer-events-none"
          style={{ left: "0%", willChange: "left" }}
        >
          <div
            className="w-4 h-10 rounded-full shadow-lg"
            style={{
              background: "white",
              boxShadow: "0 0 12px rgba(255,255,255,0.8), 0 0 24px rgba(139,92,246,0.5)",
            }}
          />
        </div>
      </div>

      {/* Zone labels */}
      <div className="flex justify-between text-white/20 text-xs mt-2 px-1">
        <span>MISS</span>
        <span className="text-yellow-400/40">GOOD</span>
        <span className="text-green-400/50">GREAT</span>
        <span className="text-violet-400/70 font-bold">PERFECT</span>
        <span className="text-green-400/50">GREAT</span>
        <span className="text-yellow-400/40">GOOD</span>
        <span>MISS</span>
      </div>
    </div>
  );
});

export default React.memo(TapBar);