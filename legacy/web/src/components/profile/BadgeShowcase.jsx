import React, { useState, useEffect } from "react";
import { motion } from "framer-motion";
import { SHOP_ITEMS } from "@/components/game/shopData";
import { getOwnedItems, getEquippedItems, equipItem } from "@/components/game/coinSystem";

export default function BadgeShowcase() {
  const [owned, setOwned] = useState([]);
  const [equipped, setEquipped] = useState({});

  useEffect(() => {
    setOwned(getOwnedItems());
    setEquipped(getEquippedItems());
  }, []);

  const allBadges = SHOP_ITEMS.badges || [];
  const ownedBadges = allBadges.filter(b => owned.includes(b.id));

  const handleEquipBadge = (badgeId) => {
    const current = equipped.badges;
    if (current === badgeId) {
      // Unequip
      equipItem("badges", null);
    } else {
      equipItem("badges", badgeId);
    }
    setEquipped(getEquippedItems());
  };

  if (ownedBadges.length === 0) {
    return (
      <div className="bg-white/5 border border-white/10 rounded-2xl p-6 text-center">
        <p className="text-3xl mb-2">🏅</p>
        <p className="text-white/40 text-sm">No badges yet</p>
        <p className="text-white/20 text-xs mt-1">Purchase badges from the Shop!</p>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      <p className="text-white/30 text-xs tracking-widest uppercase">Your Badges</p>
      <div className="grid grid-cols-3 gap-2">
        {ownedBadges.map((badge, i) => {
          const isEquipped = equipped.badges === badge.id;
          return (
            <motion.button
              key={badge.id}
              initial={{ opacity: 0, scale: 0.8 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ delay: i * 0.05 }}
              onClick={() => handleEquipBadge(badge.id)}
              className={`aspect-square rounded-xl flex flex-col items-center justify-center gap-1 border transition-all ${
                isEquipped
                  ? "bg-violet-500/20 border-violet-500/50 shadow-lg shadow-violet-500/20"
                  : "bg-white/5 border-white/10 hover:bg-white/8"
              }`}
            >
              <span className="text-2xl">{badge.icon}</span>
              <span className={`text-[10px] font-bold ${isEquipped ? "text-violet-300" : "text-white/40"}`}>
                {badge.name}
              </span>
            </motion.button>
          );
        })}
      </div>
    </div>
  );
}