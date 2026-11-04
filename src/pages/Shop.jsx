import React, { useState, useEffect } from "react";
import { createPageUrl } from "@/utils";
import { Link } from "react-router-dom";
import { motion, AnimatePresence } from "framer-motion";
import { ArrowLeft, Coins } from "lucide-react";
import { getCoins, spendCoins, getOwnedItems, addOwnedItem, getEquippedItems, equipItem } from "@/components/game/coinSystem";
import { SHOP_CATEGORIES, SHOP_ITEMS } from "@/components/game/shopData";
import ShopItemCard from "@/components/shop/ShopItemCard";
import CoinStore from "@/components/shop/CoinStore";
import { playSfx } from "@/components/game/soundEngine";
import { quickSave } from "@/components/game/playerService";

export default function Shop() {
  const [coins, setCoins] = useState(0);
  const [ownedItems, setOwnedItems] = useState([]);
  const [equipped, setEquipped] = useState({});
  const [activeTab, setActiveTab] = useState("themes");
  const [showPurchase, setShowPurchase] = useState(null);

  useEffect(() => {
    setCoins(getCoins());
    setOwnedItems(getOwnedItems());
    setEquipped(getEquippedItems());
  }, []);

  const handleBuy = (item) => {
    // Prevent double purchase — recheck ownership from localStorage
    if (getOwnedItems().includes(item.id)) return;
    if (spendCoins(item.price)) {
      addOwnedItem(item.id);
      setOwnedItems(getOwnedItems());
      setCoins(getCoins());
      playSfx("perfect");
      setShowPurchase(item);
      setTimeout(() => setShowPurchase(null), 1500);
    }
  };

  const handleEquip = (itemId) => {
    equipItem(activeTab, itemId);
    setEquipped(getEquippedItems());
    if (activeTab === "themes") {
      quickSave({ theme: itemId });
    }
    playSfx("great");
  };

  const items = SHOP_ITEMS[activeTab] || [];

  return (
    <div className="min-h-screen bg-[#0a0a0f] flex flex-col px-6 py-10">
      <div className="max-w-sm mx-auto w-full">
        {/* Header */}
        <div className="flex items-center gap-4 mb-6">
          <Link to={createPageUrl("Home")}>
            <motion.button whileTap={{ scale: 0.9 }} className="w-10 h-10 rounded-xl bg-white/5 border border-white/10 flex items-center justify-center text-white/60">
              <ArrowLeft className="w-5 h-5" />
            </motion.button>
          </Link>
          <div className="flex-1">
            <h1 className="text-2xl font-black text-white">SHOP</h1>
            <p className="text-white/30 text-xs tracking-widest">Cosmetics & Items</p>
          </div>
          <div className="flex items-center gap-1.5 bg-amber-400/10 border border-amber-400/20 rounded-full px-3 py-1.5">
            <Coins className="w-4 h-4 text-amber-400" />
            <span className="text-amber-400 text-sm font-black">{coins}</span>
          </div>
        </div>

        {/* Category Tabs */}
        <div className="flex gap-2 mb-6 overflow-x-auto pb-1 scrollbar-hide">
          {SHOP_CATEGORIES.map(cat => (
            <motion.button
              key={cat.id}
              whileTap={{ scale: 0.95 }}
              onClick={() => setActiveTab(cat.id)}
              className={`flex items-center gap-1.5 px-4 py-2 rounded-xl text-xs font-bold whitespace-nowrap transition-all ${
                activeTab === cat.id
                  ? "bg-violet-500/20 border border-violet-500/40 text-violet-300"
                  : "bg-white/5 border border-white/10 text-white/40"
              }`}
            >
              <span>{cat.icon}</span>
              {cat.label}
            </motion.button>
          ))}
        </div>

        {/* Items List */}
        <div className="flex flex-col gap-3">
          {items.map((item, i) => {
            const isOwned = ownedItems.includes(item.id);
            const isEquipped = equipped[activeTab] === item.id || (item.price === 0 && !equipped[activeTab]);
            const canAfford = coins >= item.price;

            return (
              <ShopItemCard
                key={item.id}
                item={item}
                category={activeTab}
                isOwned={isOwned}
                isEquipped={isEquipped}
                canAfford={canAfford}
                onBuy={handleBuy}
                onEquip={handleEquip}
                index={i}
              />
            );
          })}
        </div>

        {/* Coin Store Section */}
        <div className="mt-8 pt-6 border-t border-white/5">
          <CoinStore onCoinsChange={setCoins} />
        </div>

        {/* Earn more coins hint */}
        <div className="mt-6 text-center">
          <p className="text-white/20 text-xs tracking-widest">Earn coins by playing Classic mode</p>
        </div>
      </div>

      {/* Purchase celebration */}
      <AnimatePresence>
        {showPurchase && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 flex items-center justify-center z-50 pointer-events-none"
          >
            <motion.div
              initial={{ scale: 0.5, y: 40 }}
              animate={{ scale: 1, y: 0 }}
              exit={{ scale: 0.8, opacity: 0 }}
              className="bg-[#0a0a0f] border-2 border-amber-400/60 rounded-3xl px-10 py-8 text-center shadow-2xl"
            >
              <p className="text-5xl mb-3">{showPurchase.icon || "🎉"}</p>
              <p className="text-amber-400 font-black text-2xl">PURCHASED!</p>
              <p className="text-white/60 text-sm mt-1">{showPurchase.name}</p>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}