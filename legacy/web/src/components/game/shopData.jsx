// All purchasable cosmetic items

export const SHOP_CATEGORIES = [
  { id: "themes", label: "Themes", icon: "🎨" },
  { id: "animations", label: "Tap FX", icon: "✨" },
  { id: "trails", label: "Trails", icon: "🌊" },
  { id: "badges", label: "Badges", icon: "🏅" },
  { id: "avatars", label: "Avatars", icon: "👤" },
];

export const RARITY = {
  common: { label: "Common", color: "text-white/50", border: "border-white/10", bg: "bg-white/5" },
  rare: { label: "Rare", color: "text-blue-400", border: "border-blue-500/30", bg: "bg-blue-500/5" },
  epic: { label: "Epic", color: "text-purple-400", border: "border-purple-500/30", bg: "bg-purple-500/5" },
  legendary: { label: "Legendary", color: "text-amber-400", border: "border-amber-500/30", bg: "bg-amber-500/5" },
};

export const SHOP_ITEMS = {
  themes: [
    { id: "default", name: "Nebula", price: 0, preview: "from-violet-500 to-cyan-400", description: "Default theme", rarity: "common" },
    { id: "neon", name: "Neon", price: 150, preview: "from-green-400 to-lime-300", description: "Electric green glow", rarity: "common" },
    { id: "fire", name: "Inferno", price: 300, preview: "from-orange-500 to-red-400", description: "Blazing hot flames", rarity: "rare" },
    { id: "ice", name: "Arctic", price: 400, preview: "from-sky-400 to-blue-300", description: "Frozen tundra vibes", rarity: "rare" },
    { id: "gold", name: "Gold Rush", price: 600, preview: "from-yellow-400 to-amber-300", description: "Pure luxury", rarity: "epic" },
    { id: "galaxy", name: "Galaxy", price: 800, preview: "from-purple-600 to-pink-400", description: "Deep space", rarity: "epic" },
    { id: "midnight", name: "Midnight", price: 500, preview: "from-indigo-900 to-slate-800", description: "Dark and mysterious", rarity: "rare" },
    { id: "sunset", name: "Sunset", price: 700, preview: "from-rose-500 to-yellow-400", description: "Golden hour", rarity: "epic" },
    { id: "matrix", name: "Matrix", price: 1200, preview: "from-green-600 to-emerald-900", description: "Enter the code", rarity: "legendary" },
  ],
  animations: [
    { id: "anim_default", name: "Classic Pulse", price: 0, icon: "💫", description: "Default tap animation", rarity: "common" },
    { id: "anim_ripple", name: "Ripple Wave", price: 200, icon: "🌊", description: "Expanding ring effect", rarity: "common" },
    { id: "anim_spark", name: "Spark Burst", price: 350, icon: "⚡", description: "Electric spark explosion", rarity: "rare" },
    { id: "anim_hearts", name: "Heart Shower", price: 300, icon: "💖", description: "Burst of hearts", rarity: "rare" },
    { id: "anim_stars", name: "Stardust", price: 500, icon: "🌟", description: "Cosmic star particles", rarity: "epic" },
    { id: "anim_confetti", name: "Confetti Pop", price: 450, icon: "🎉", description: "Party confetti burst", rarity: "epic" },
    { id: "anim_shatter", name: "Shatter", price: 800, icon: "💥", description: "Glass shatter effect", rarity: "legendary" },
  ],
  trails: [
    { id: "trail_default", name: "No Trail", price: 0, icon: "➖", description: "Clean look", rarity: "common" },
    { id: "trail_glow", name: "Glow Trail", price: 250, icon: "💡", description: "Soft glowing trail", rarity: "common" },
    { id: "trail_fire", name: "Fire Trail", price: 400, icon: "🔥", description: "Flaming hot trail", rarity: "rare" },
    { id: "trail_rainbow", name: "Rainbow Trail", price: 500, icon: "🌈", description: "Color-shifting trail", rarity: "epic" },
    { id: "trail_pixel", name: "Pixel Trail", price: 350, icon: "👾", description: "Retro pixel particles", rarity: "rare" },
    { id: "trail_lightning", name: "Lightning Trail", price: 600, icon: "⚡", description: "Electric bolt trail", rarity: "epic" },
    { id: "trail_galaxy", name: "Galaxy Trail", price: 1000, icon: "🌌", description: "Cosmic stardust trail", rarity: "legendary" },
  ],
  badges: [
    { id: "badge_rookie", name: "Rookie", price: 100, icon: "🌱", description: "Just getting started", rarity: "common" },
    { id: "badge_pro", name: "Pro Player", price: 300, icon: "⭐", description: "Serious contender", rarity: "rare" },
    { id: "badge_legend", name: "Legend", price: 600, icon: "👑", description: "Ultimate status", rarity: "epic" },
    { id: "badge_skull", name: "Death Defier", price: 400, icon: "💀", description: "Sudden Death master", rarity: "rare" },
    { id: "badge_combo", name: "Combo King", price: 400, icon: "🔗", description: "Combo Frenzy champion", rarity: "rare" },
    { id: "badge_diamond", name: "Diamond", price: 1000, icon: "💎", description: "The rarest badge", rarity: "legendary" },
    { id: "badge_flame", name: "On Fire", price: 500, icon: "🔥", description: "Hot streak master", rarity: "epic" },
    { id: "badge_galaxy", name: "Cosmic", price: 800, icon: "🌌", description: "Reaches for the stars", rarity: "epic" },
    { id: "badge_crown", name: "Royal", price: 1500, icon: "🏰", description: "Untouchable royalty", rarity: "legendary" },
  ],
  avatars: [
    { id: "av_default", name: "Default", price: 0, icon: "😊", description: "Classic smiley", rarity: "common" },
    { id: "av_cool", name: "Cool Shades", price: 200, icon: "😎", description: "Sunglasses on", rarity: "common" },
    { id: "av_ninja", name: "Ninja", price: 350, icon: "🥷", description: "Silent and deadly", rarity: "rare" },
    { id: "av_robot", name: "Robot", price: 400, icon: "🤖", description: "Mechanical precision", rarity: "rare" },
    { id: "av_alien", name: "Alien", price: 500, icon: "👽", description: "Out of this world", rarity: "epic" },
    { id: "av_wizard", name: "Wizard", price: 600, icon: "🧙", description: "Magical tapper", rarity: "epic" },
    { id: "av_crown", name: "King", price: 800, icon: "🤴", description: "Royalty vibes", rarity: "epic" },
    { id: "av_devil", name: "Devil", price: 700, icon: "😈", description: "Devilish skills", rarity: "epic" },
    { id: "av_unicorn", name: "Unicorn", price: 1000, icon: "🦄", description: "Mythical player", rarity: "legendary" },
    { id: "av_dragon", name: "Dragon", price: 1500, icon: "🐉", description: "Legendary beast", rarity: "legendary" },
  ],
};