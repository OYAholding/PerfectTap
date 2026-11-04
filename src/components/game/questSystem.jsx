// Daily quest system — reads/writes through playerService cache

import { getCachedProfile, quickSave } from "./playerService";

const QUEST_TEMPLATES = [
  { id: "play_3",       title: "Play 3 Games",          icon: "🎮", description: "Complete 3 games in any mode",       target: 3, track: "games",    reward: { type: "coins", amount: 50 },  difficulty: "easy" },
  { id: "play_5",       title: "Play 5 Games",          icon: "🎮", description: "Complete 5 games in any mode",       target: 5, track: "games",    reward: { type: "coins", amount: 100 }, difficulty: "medium" },
  { id: "score_500",    title: "Score 500 Points",      icon: "🎯", description: "Reach 500 points in a single game",  target: 500, track: "score",  reward: { type: "coins", amount: 60 },  difficulty: "easy" },
  { id: "score_1000",   title: "Score 1000 Points",     icon: "🎯", description: "Reach 1000 points in a single game", target: 1000, track: "score", reward: { type: "coins", amount: 120 }, difficulty: "medium" },
  { id: "score_2000",   title: "Score 2000 Points",     icon: "🏆", description: "Reach 2000 points in a single game", target: 2000, track: "score", reward: { type: "coins", amount: 200 }, difficulty: "hard" },
  { id: "combo_5",      title: "Get 5x Combo",          icon: "🔥", description: "Reach a 5x combo in any game",       target: 5, track: "combo",    reward: { type: "coins", amount: 40 },  difficulty: "easy" },
  { id: "combo_10",     title: "Get 10x Combo",         icon: "🔥", description: "Reach a 10x combo in any game",      target: 10, track: "combo",   reward: { type: "coins", amount: 80 },  difficulty: "medium" },
  { id: "combo_20",     title: "Get 20x Combo",         icon: "💥", description: "Reach a 20x combo in any game",      target: 20, track: "combo",   reward: { type: "coins", amount: 150 }, difficulty: "hard" },
  { id: "earn_100",     title: "Earn 100 Coins",        icon: "🪙", description: "Earn 100 coins from games today",    target: 100, track: "coins",  reward: { type: "coins", amount: 50 },  difficulty: "easy" },
  { id: "earn_300",     title: "Earn 300 Coins",        icon: "💰", description: "Earn 300 coins from games today",    target: 300, track: "coins",  reward: { type: "coins", amount: 100 }, difficulty: "medium" },
  { id: "perfect_10",   title: "Land 10 Perfects",      icon: "✨", description: "Get 10 Perfect taps in one game",    target: 10, track: "perfects",reward: { type: "coins", amount: 70 },  difficulty: "easy" },
  { id: "perfect_25",   title: "Land 25 Perfects",      icon: "⭐", description: "Get 25 Perfect taps in one game",    target: 25, track: "perfects",reward: { type: "coins", amount: 150 }, difficulty: "hard" },
  { id: "play_duel",    title: "Play a Duel",           icon: "⚔️", description: "Complete 1 duel match",              target: 1, track: "duels",    reward: { type: "coins", amount: 80 },  difficulty: "medium" },
  { id: "sudden_death", title: "Survive Sudden Death",  icon: "💀", description: "Score 300+ in Sudden Death",         target: 300, track: "sudden_score", reward: { type: "coins", amount: 100 }, difficulty: "hard" },
];

function getDayKey() {
  return new Date().toISOString().slice(0, 10);
}

function seededRandom(seed) {
  let x = Math.sin(seed) * 10000;
  return x - Math.floor(x);
}

function pickDailyQuests(dayKey) {
  const seed = dayKey.split("-").join("") * 1;
  const shuffled = [...QUEST_TEMPLATES].sort((a, b) => seededRandom(seed + a.id.length) - seededRandom(seed + b.id.length));
  const easy = shuffled.find(q => q.difficulty === "easy");
  const medium = shuffled.find(q => q.difficulty === "medium");
  const hard = shuffled.find(q => q.difficulty === "hard");
  return [easy, medium, hard].filter(Boolean);
}

export function getDailyQuests() {
  const today = getDayKey();
  const p = getCachedProfile();
  let data = p?.quest_data || null;

  if (!data || data.day !== today) {
    const quests = pickDailyQuests(today).map(q => ({
      ...q,
      progress: 0,
      completed: false,
      claimed: false,
    }));
    data = { day: today, quests, dailyCoinsEarned: 0 };
    quickSave({ quest_data: data });
  }

  return data;
}

export function updateQuestProgress({ games = 0, score = 0, combo = 0, coins = 0, perfects = 0, duels = 0, suddenScore = 0 }) {
  const data = getDailyQuests();
  data.dailyCoinsEarned += coins;

  data.quests.forEach(q => {
    if (q.completed) return;
    
    let newProgress = q.progress;
    switch (q.track) {
      case "games":   newProgress += games; break;
      case "score":   newProgress = Math.max(newProgress, score); break;
      case "combo":   newProgress = Math.max(newProgress, combo); break;
      case "coins":   newProgress = data.dailyCoinsEarned; break;
      case "perfects": newProgress = Math.max(newProgress, perfects); break;
      case "duels":   newProgress += duels; break;
      case "sudden_score": newProgress = Math.max(newProgress, suddenScore); break;
    }
    q.progress = newProgress;
    if (q.progress >= q.target) q.completed = true;
  });

  quickSave({ quest_data: data });
  return data;
}

export function claimQuestReward(questId) {
  const data = getDailyQuests();
  const quest = data.quests.find(q => q.id === questId);
  if (!quest || !quest.completed || quest.claimed) return null;
  quest.claimed = true;
  quickSave({ quest_data: data });
  return quest.reward;
}