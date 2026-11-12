import React from "react";
import { Link, useLocation } from "react-router-dom";
import { Home, ShoppingBag, Trophy, User } from "lucide-react";

const TABS = [
  { path: "/Home", label: "Home", icon: Home },
  { path: "/Shop", label: "Shop", icon: ShoppingBag },
  { path: "/Leaderboard", label: "Scores", icon: Trophy },
  { path: "/Profile", label: "Profile", icon: User },
];

// Pages where the bottom nav should be hidden (gameplay, fullscreen flows)
const HIDDEN_ON = ["/Game", "/SetUsername", "/Matchmaking", "/Spectate", "/DuelResults", "/ChallengeComplete"];

export default function BottomNav() {
  const location = useLocation();
  const currentPath = location.pathname;

  if (HIDDEN_ON.some(p => currentPath.startsWith(p))) return null;

  return (
    <nav
      className="fixed bottom-0 left-0 right-0 z-50 bg-[#0a0a0f]/95 backdrop-blur-md border-t border-white/10"
      style={{ paddingBottom: "env(safe-area-inset-bottom)" }}
    >
      <div className="max-w-md mx-auto flex items-center justify-around h-14">
        {TABS.map(tab => {
          const Icon = tab.icon;
          const active = currentPath === tab.path || (tab.path === "/Home" && currentPath === "/");
          return (
            <Link
              key={tab.path}
              to={tab.path}
              className={`flex flex-col items-center gap-0.5 px-4 py-1.5 transition-colors ${
                active ? "text-violet-400" : "text-white/30"
              }`}
            >
              <Icon className="w-5 h-5" strokeWidth={active ? 2.5 : 2} />
              <span className="text-[10px] font-semibold">{tab.label}</span>
            </Link>
          );
        })}
      </div>
    </nav>
  );
}