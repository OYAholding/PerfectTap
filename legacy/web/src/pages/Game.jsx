import React, { useState, useEffect, useRef, useCallback } from "react";
import { createPageUrl } from "@/utils";
import { useNavigate } from "react-router-dom";
import { motion, AnimatePresence } from "framer-motion";
import TapBar from "@/components/game/TapBar";
const TapBarMemo = TapBar;
import ScoreDisplay from "@/components/game/ScoreDisplay";
import LivesDisplay from "@/components/game/LivesDisplay";
import HitFeedback from "@/components/game/HitFeedback";
import ComboDisplay from "@/components/game/ComboDisplay";
import ReviveModal from "@/components/game/ReviveModal";
import { playSfx, startBgMusic, stopBgMusic } from "@/components/game/soundEngine";
import { Leaf, Repeat, Users, Timer, Skull, Link as LinkIcon } from "lucide-react";
import { addCoins, calcGameCoins } from "@/components/game/coinSystem";
import { recordGame } from "@/components/game/statsSystem";
import { updateQuestProgress } from "@/components/game/questSystem";
import { getCachedProfile, quickSave, flushSave, getProfileId } from "@/components/game/playerService";
import { submitScoreViaBackend } from "@/components/game/duelService";
import { awardXP, calcGameXP } from "@/components/game/xpSystem";
import { checkAchievements } from "@/components/game/achievementSystem";
import { awardSeasonXP, calcSeasonXP } from "@/components/game/seasonSystem";
import ParticleExplosion from "@/components/game/particleEffects";

const THEMES = {
  default: { bar: "from-violet-500 to-cyan-400", indicator: "#fff", target: "#a78bfa" },
  neon: { bar: "from-green-400 to-lime-300", indicator: "#fff", target: "#4ade80" },
  fire: { bar: "from-orange-500 to-red-400", indicator: "#fff", target: "#fb923c" },
  ice: { bar: "from-sky-400 to-blue-300", indicator: "#fff", target: "#38bdf8" },
  gold: { bar: "from-yellow-400 to-amber-300", indicator: "#fff", target: "#fbbf24" },
  galaxy: { bar: "from-purple-600 to-pink-400", indicator: "#fff", target: "#c084fc" },
};

function getAccuracy(pos) {
  const dist = Math.abs(pos - 50);
  if (dist <= 4) return "PERFECT";
  if (dist <= 10) return "GREAT";
  if (dist <= 20) return "GOOD";
  return "MISS";
}

function getPoints(accuracy) {
  if (accuracy === "PERFECT") return 100;
  if (accuracy === "GREAT") return 70;
  if (accuracy === "GOOD") return 40;
  return 0;
}

export default function Game() {
  const navigate = useNavigate();

  const urlParams = new URLSearchParams(window.location.search);
  const gameMode = urlParams.get("mode") || "classic";

  const isDuel = gameMode === "duel";
  const isEndless = gameMode === "endless";
  const isZen = gameMode === "zen";
  const isTimed = gameMode === "timed";
  const isSuddenDeath = gameMode === "sudden_death";
  const isComboFrenzy = gameMode === "combo_frenzy";
  const isClassic = gameMode === "classic" || isDuel;
  const TIMED_DURATION = 60; // seconds

  const [score, setScore] = useState(0);
  const [lives, setLives] = useState(isZen ? Infinity : isSuddenDeath ? 1 : 3);
  const [timeLeft, setTimeLeft] = useState(TIMED_DURATION);
  const timeLeftRef = useRef(TIMED_DURATION);
  const [combo, setCombo] = useState(0);
  const [maxCombo, setMaxCombo] = useState(0);
  const [taps, setTaps] = useState(0);
  const tapsRef = useRef(0);
  const [feedback, setFeedback] = useState(null);
  const [gameOver, setGameOver] = useState(false);
  const [started, setStarted] = useState(false);
  const [countdown, setCountdown] = useState(3);
  const [speed, setSpeed] = useState(isZen ? 1.6 : isTimed ? 1.0 : isSuddenDeath ? 0.9 : 1.2);
  const [theme, setTheme] = useState("default");
  const [scoreMultiplier, setScoreMultiplier] = useState(1);
  const [activeChallenge, setActiveChallenge] = useState(null);
  const gameStartTimeRef = useRef(Date.now());
  const perfectStreakRef = useRef(0);
  const missCountRef = useRef(0);
  const totalTapsRef = useRef(0);
  const perfectCountInFirstNRef = useRef(0);

  // Revive state
  const [showReviveModal, setShowReviveModal] = useState(false);
  const hasUsedReviveRef = useRef(false);
  const [paused, setPaused] = useState(false);

  // Zen mode stats
  const [zenPerfects, setZenPerfects] = useState(0);
  const [zenGreats, setZenGreats] = useState(0);
  const [zenTotal, setZenTotal] = useState(0);

  // Particle effects
  const [particleTrigger, setParticleTrigger] = useState(0);
  const [particleAccuracy, setParticleAccuracy] = useState(null);

  const tapBarRef = useRef(null);
  const posRef = useRef(0);
  const dirRef = useRef(1);
  const animRef = useRef(null);
  const lastTimeRef = useRef(null);
  const speedRef = useRef(isZen ? 1.6 : isTimed ? 1.0 : isSuddenDeath ? 0.9 : 1.2);
  const gameOverRef = useRef(false);
  const livesRef = useRef(isZen ? Infinity : isSuddenDeath ? 1 : 3);
  const scoreRef = useRef(0);
  const comboRef = useRef(0);
  const pausedRef = useRef(false);

  useEffect(() => {
    const p = getCachedProfile();
    const saved = p?.theme || "default";
    setTheme(THEMES[saved] ? saved : "default");

    if (!isZen) {
      const boost = p?.boost || null;
      if (boost && !boost.used) {
        setScoreMultiplier(boost.value);
        quickSave({ boost: { ...boost, used: true } });
      }
    }

    if (isClassic && !isDuel) {
      const challengeId = p?.active_challenge || "";
      if (challengeId) {
        import("./Challenges").then(mod => {
          const found = mod.CHALLENGES.find(c => c.id === challengeId);
          if (found) setActiveChallenge(found);
        });
      }
    }

    gameStartTimeRef.current = Date.now();
    startBgMusic();
    return () => stopBgMusic();
  }, []);

  // Countdown
  useEffect(() => {
    if (!started && countdown > 0) {
      playSfx("countdown");
      const t = setTimeout(() => setCountdown(c => c - 1), 1000);
      return () => clearTimeout(t);
    } else if (!started && countdown === 0) {
      playSfx("countdownGo");
      setStarted(true);
    }
  }, [started, countdown]);

  // Game animation loop
  useEffect(() => {
    if (!started || gameOver) return;

    const animate = (timestamp) => {
      if (pausedRef.current) {
        lastTimeRef.current = null;
        animRef.current = requestAnimationFrame(animate);
        return;
      }

      if (!lastTimeRef.current) lastTimeRef.current = timestamp;
      const delta = (timestamp - lastTimeRef.current) / 1000;
      lastTimeRef.current = timestamp;

      const step = (delta / speedRef.current) * 100;
      posRef.current += dirRef.current * step;

      if (posRef.current >= 100) { posRef.current = 100; dirRef.current = -1; }
      else if (posRef.current <= 0) { posRef.current = 0; dirRef.current = 1; }

      // Direct DOM update — bypasses React re-render entirely
      if (tapBarRef.current) tapBarRef.current.setPosition(posRef.current);

      // Time-based challenge check (classic only)
      if (isClassic && activeChallenge?.condition?.type === "time") {
        const elapsed = (Date.now() - gameStartTimeRef.current) / 1000;
        if (elapsed >= activeChallenge.condition.seconds && livesRef.current > 0) {
          completeChallenge();
          return;
        }
      }

      // Endless: gradually increase speed (update UI only when visually different)
      if (isEndless) {
        const elapsed = (Date.now() - gameStartTimeRef.current) / 1000;
        const newSpeed = Math.max(0.2, 1.2 - elapsed * 0.005);
        if (Math.abs(newSpeed - speedRef.current) > 0.01) {
          speedRef.current = newSpeed;
          setSpeed(newSpeed);
        } else {
          speedRef.current = newSpeed;
        }
      }

      // Timed: countdown timer (update UI only when the displayed second changes)
      if (isTimed) {
        const elapsed = (Date.now() - gameStartTimeRef.current) / 1000;
        const remaining = Math.max(0, TIMED_DURATION - elapsed);
        if (Math.ceil(remaining) !== Math.ceil(timeLeftRef.current)) {
          timeLeftRef.current = remaining;
          setTimeLeft(remaining);
        }
        if (remaining <= 0 && !gameOverRef.current) {
          triggerTimedEnd();
          return;
        }
      }

      animRef.current = requestAnimationFrame(animate);
    };

    animRef.current = requestAnimationFrame(animate);
    return () => {
      if (animRef.current) cancelAnimationFrame(animRef.current);
      lastTimeRef.current = null;
    };
  }, [started, gameOver]);

  const completeChallenge = useCallback(() => {
    if (!activeChallenge) return;
    const p = getCachedProfile();
    const done = [...(p?.challenges_done || [])];
    if (!done.includes(activeChallenge.id)) {
      done.push(activeChallenge.id);
    }
    const updates = { challenges_done: done, active_challenge: "" };
    const reward = activeChallenge.reward;
    if (reward.type === "boost") {
      updates.boost = { value: reward.value, used: false, games: reward.games };
    } else if (reward.type === "theme") {
      const owned = [...(p?.owned_items || [])];
      if (!owned.includes(reward.themeId)) {
        owned.push(reward.themeId);
        updates.owned_items = owned;
      }
    }
    quickSave(updates);
    gameOverRef.current = true;
    cancelAnimationFrame(animRef.current);
    playSfx("challengeComplete");
    navigate(createPageUrl("ChallengeComplete") + `?id=${activeChallenge.id}`);
  }, [activeChallenge, navigate]);

  // Track maxCombo in a ref for reliable access in callbacks
  const maxComboRef = useRef(0);
  useEffect(() => { maxComboRef.current = maxCombo; }, [maxCombo]);

  /** Trigger final game over — save scores and navigate away */
  const triggerGameOver = useCallback(async () => {
    gameOverRef.current = true;
    setGameOver(true);

    const currentMaxCombo = maxComboRef.current;

    // Award coins — ONLY Classic mode earns coins
    let earned = 0;
    if (isClassic && !isDuel) {
      earned = calcGameCoins(scoreRef.current, currentMaxCombo, "classic");
      if (earned > 0) {
        addCoins(earned);
        localStorage.setItem("perfecttap_last_coins_earned", earned.toString());
      }
    }

    // Track stats & quest progress
    if (!isZen) {
      recordGame({
        mode: gameMode,
        score: scoreRef.current,
        maxCombo: currentMaxCombo,
        coinsEarned: earned,
        perfectCount: perfectCountInFirstNRef.current,
        tapCount: totalTapsRef.current,
      });
      updateQuestProgress({
        games: 1,
        score: scoreRef.current,
        combo: currentMaxCombo,
        coins: earned,
        perfects: perfectCountInFirstNRef.current,
        duels: isDuel ? 1 : 0,
        suddenScore: isSuddenDeath ? scoreRef.current : 0,
      });
    }

    const p = getCachedProfile();
    const profileUpdates = {};

    if (isDuel) {
      const duelId = localStorage.getItem("perfecttap_duel_id");
      const duelRole = localStorage.getItem("perfecttap_duel_role");
      if (duelId && duelRole) {
        // Submit duel score via backend (validated)
        await submitScoreViaBackend({
          mode: "duel",
          score: scoreRef.current,
          maxCombo: currentMaxCombo,
          duelId,
          duelRole,
        });
      }
    } else {
      // Submit solo score via backend (validated best score update)
      submitScoreViaBackend({
        mode: gameMode,
        score: scoreRef.current,
        maxCombo: currentMaxCombo,
      });

      // Also update local cache for immediate UI feedback
      if (isClassic && scoreRef.current > (p?.best_classic || 0)) {
        profileUpdates.best_classic = scoreRef.current;
      }
      if (isEndless && scoreRef.current > (p?.best_endless || 0)) {
        profileUpdates.best_endless = scoreRef.current;
      }
      if (isSuddenDeath && scoreRef.current > (p?.best_sudden || 0)) {
        profileUpdates.best_sudden = scoreRef.current;
      }
      if (isComboFrenzy && scoreRef.current > (p?.best_combofrenzy || 0)) {
        profileUpdates.best_combofrenzy = scoreRef.current;
      }
      if (isClassic) {
        const history = [...(p?.score_history || [])];
        history.unshift({ score: scoreRef.current, date: new Date().toISOString() });
        profileUpdates.score_history = history.slice(0, 10);
      }
    }

    if (Object.keys(profileUpdates).length > 0) {
      quickSave(profileUpdates);
    }

    // Award XP
    if (!isZen) {
      const xpEarned = calcGameXP(scoreRef.current, currentMaxCombo, gameMode);
      const xpResult = awardXP(xpEarned);
      localStorage.setItem("perfecttap_last_xp_earned", xpEarned.toString());
      if (xpResult.leveledUp) {
        localStorage.setItem("perfecttap_leveled_up", xpResult.newLevel.toString());
      }
      // Season XP
      const sxp = calcSeasonXP(scoreRef.current, currentMaxCombo, gameMode);
      awardSeasonXP(sxp);
    }

    // Check achievements
    const gameData = { score: scoreRef.current, maxCombo: currentMaxCombo, mode: gameMode };
    const newAchievements = checkAchievements(gameData);
    if (newAchievements.length > 0) {
      localStorage.setItem("perfecttap_new_achievements", JSON.stringify(newAchievements.map(a => a.title)));
    }

    await flushSave();
  }, [isClassic, isEndless, isDuel, isSuddenDeath, isComboFrenzy, isZen, gameMode]);

  /** Called when player runs out of lives — decide revive or game over */
  const handleOutOfLives = useCallback(() => {
    if (!hasUsedReviveRef.current && !isZen) {
      pausedRef.current = true;
      setPaused(true);
      setShowReviveModal(true);
    } else {
      triggerGameOver();
    }
  }, [isZen, triggerGameOver]);

  /** Player accepted revive */
  const handleRevive = useCallback(() => {
    hasUsedReviveRef.current = true;
    setShowReviveModal(false);

    // Restore lives based on mode
    if (isSuddenDeath) {
      livesRef.current = 1;
      setLives(1);
    } else {
      livesRef.current = 3;
      setLives(3);
    }
    // Timed: also add 15 bonus seconds
    if (isTimed) {
      gameStartTimeRef.current += 15 * 1000;
      setTimeLeft(prev => prev + 15);
    }

    pausedRef.current = false;
    setPaused(false);
    lastTimeRef.current = null;
  }, [isSuddenDeath, isTimed]);

  /** Player declined revive — force final game over */
  const handleDeclineRevive = useCallback(() => {
    setShowReviveModal(false);
    hasUsedReviveRef.current = true;
    pausedRef.current = false;
    setPaused(false);
    triggerGameOver();
  }, [triggerGameOver]);

  const handleTap = useCallback(() => {
    if (!started || gameOverRef.current || pausedRef.current) return;

    const pos = posRef.current;
    const accuracy = getAccuracy(pos);
    const points = getPoints(accuracy);

    const prevCombo = comboRef.current;
    let newCombo = prevCombo;
    if (isComboFrenzy) {
      // In Combo Frenzy, GOOD also keeps the combo alive
      if (accuracy === "PERFECT" || accuracy === "GREAT" || accuracy === "GOOD") {
        newCombo += 1;
      } else {
        newCombo = 0;
      }
    } else {
      if (accuracy === "PERFECT" || accuracy === "GREAT") {
        newCombo += 1;
      } else {
        newCombo = 0;
      }
    }
    comboRef.current = newCombo;
    setCombo(newCombo);
    setMaxCombo(prev => Math.max(prev, newCombo));

    let multiplier;
    if (isComboFrenzy) {
      // Combo Frenzy: much heavier combo multipliers
      multiplier = newCombo >= 20 ? 6 : newCombo >= 15 ? 5 : newCombo >= 10 ? 4 : newCombo >= 5 ? 3 : newCombo >= 3 ? 2 : 1;
    } else {
      multiplier = newCombo >= 5 ? 2 : newCombo >= 3 ? 1.5 : 1;
    }
    const finalPoints = isZen ? 0 : Math.round(points * multiplier * scoreMultiplier);

    if (!isZen) {
      scoreRef.current += finalPoints;
      setScore(scoreRef.current);
    }

    if (isZen) {
      setZenTotal(prev => prev + 1);
      if (accuracy === "PERFECT") setZenPerfects(prev => prev + 1);
      else if (accuracy === "GREAT") setZenGreats(prev => prev + 1);
    }

    if (accuracy === "PERFECT") {
      perfectStreakRef.current += 1;
    } else {
      perfectStreakRef.current = 0;
    }

    if (accuracy === "MISS") missCountRef.current += 1;
    totalTapsRef.current += 1;

    if (accuracy === "PERFECT") perfectCountInFirstNRef.current += 1;

    if (isClassic && activeChallenge) {
      const cond = activeChallenge.condition;
      const level = Math.min(20, Math.floor((1.2 - speedRef.current) / 0.08) + 1);
      let completed = false;

      if (cond.type === "combo" && newCombo >= cond.target) completed = true;
      if (cond.type === "perfect_streak" && perfectStreakRef.current >= cond.target) completed = true;
      if (cond.type === "score" && scoreRef.current >= cond.target) completed = true;
      if (cond.type === "score_at_speed" && scoreRef.current >= cond.score && level >= cond.minLevel) completed = true;
      if (cond.type === "no_miss" && missCountRef.current === 0 && totalTapsRef.current >= cond.taps) completed = true;
      if (cond.type === "score_in_time") {
        const elapsed = (Date.now() - gameStartTimeRef.current) / 1000;
        if (scoreRef.current >= cond.score && elapsed <= cond.seconds) completed = true;
      }
      if (cond.type === "perfect_in_first_n" && totalTapsRef.current <= cond.taps && perfectCountInFirstNRef.current >= cond.perfectCount) completed = true;
      if (cond.type === "score_no_miss" && missCountRef.current === 0 && scoreRef.current >= cond.score) completed = true;

      if (completed) {
        completeChallenge();
        return;
      }
    }

    // All modes (except Zen) lose a life on miss
    if (accuracy === "MISS" && !isZen) {
      const newLives = livesRef.current - 1;
      livesRef.current = newLives;
      setLives(newLives);
      if (newLives <= 0) {
        handleOutOfLives();
      }
    }

    if (!isZen) {
      tapsRef.current += 1;
      const newTaps = tapsRef.current;
      setTaps(newTaps);

      if (isSuddenDeath && newTaps % 3 === 0) {
        // Sudden Death: speed increases much faster (every 3 taps)
        const newSpeed = Math.max(0.15, speedRef.current - 0.1);
        speedRef.current = newSpeed;
        setSpeed(newSpeed);
      } else if (!isEndless && !isTimed && !isSuddenDeath && !isComboFrenzy && newTaps % 5 === 0) {
        const newSpeed = Math.max(0.3, speedRef.current - 0.08);
        speedRef.current = newSpeed;
        setSpeed(newSpeed);
      }
    }

    setFeedback({ accuracy, points: finalPoints, id: Date.now() });

    // Trigger particle effects for PERFECT/GREAT
    if (accuracy === "PERFECT" || accuracy === "GREAT") {
      setParticleAccuracy(accuracy);
      setParticleTrigger(prev => prev + 1);
    }

    if (accuracy === "MISS" && prevCombo >= 3) {
      playSfx("comboBreak");
    } else if (accuracy === "MISS") {
      playSfx("miss");
    } else if (newCombo === 5 || newCombo === 10 || newCombo === 20) {
      playSfx("comboMilestone");
    } else {
      playSfx(accuracy.toLowerCase());
    }
  }, [started, isZen, isClassic, isEndless, isTimed, isSuddenDeath, isComboFrenzy, scoreMultiplier, activeChallenge, completeChallenge, handleOutOfLives]);

  // Navigate to game over
  useEffect(() => {
    if (gameOver) {
      if (isDuel) {
        navigate(createPageUrl("DuelResults"));
      } else if (isClassic || isEndless || isTimed || isSuddenDeath || isComboFrenzy) {
        navigate(createPageUrl("GameOver") + `?score=${scoreRef.current}&combo=${maxComboRef.current}&mode=${gameMode}`);
      }
    }
  }, [gameOver]);

  const triggerTimedEnd = useCallback(() => {
    gameOverRef.current = true;
    cancelAnimationFrame(animRef.current);
    const p = getCachedProfile();
    if (scoreRef.current > (p?.best_timed || 0)) {
      quickSave({ best_timed: scoreRef.current });
    }

    recordGame({ mode: "timed", score: scoreRef.current, maxCombo: maxComboRef.current, coinsEarned: 0, perfectCount: perfectCountInFirstNRef.current, tapCount: totalTapsRef.current });
    updateQuestProgress({ games: 1, score: scoreRef.current, combo: maxComboRef.current, coins: 0, perfects: perfectCountInFirstNRef.current });
    submitScoreViaBackend({ mode: "timed", score: scoreRef.current, maxCombo: maxComboRef.current });
    flushSave();

    navigate(createPageUrl("GameOver") + `?score=${scoreRef.current}&combo=${maxComboRef.current}&mode=timed`);
  }, [navigate]);

  const handleEndlessQuit = () => {
    gameOverRef.current = true;
    cancelAnimationFrame(animRef.current);
    const p = getCachedProfile();
    if (scoreRef.current > (p?.best_endless || 0)) {
      quickSave({ best_endless: scoreRef.current });
    }

    recordGame({ mode: "endless", score: scoreRef.current, maxCombo: maxComboRef.current, coinsEarned: 0, perfectCount: perfectCountInFirstNRef.current, tapCount: totalTapsRef.current });
    updateQuestProgress({ games: 1, score: scoreRef.current, combo: maxComboRef.current, coins: 0, perfects: perfectCountInFirstNRef.current });
    submitScoreViaBackend({ mode: "endless", score: scoreRef.current, maxCombo: maxComboRef.current });
    flushSave();

    navigate(createPageUrl("GameOver") + `?score=${scoreRef.current}&combo=${maxComboRef.current}&mode=endless`);
  };

  const handleComboFrenzyQuit = () => {
    gameOverRef.current = true;
    cancelAnimationFrame(animRef.current);
    const p = getCachedProfile();
    if (scoreRef.current > (p?.best_combofrenzy || 0)) {
      quickSave({ best_combofrenzy: scoreRef.current });
    }

    recordGame({ mode: "combo_frenzy", score: scoreRef.current, maxCombo: maxComboRef.current, coinsEarned: 0, perfectCount: perfectCountInFirstNRef.current, tapCount: totalTapsRef.current });
    updateQuestProgress({ games: 1, score: scoreRef.current, combo: maxComboRef.current, coins: 0, perfects: perfectCountInFirstNRef.current });
    submitScoreViaBackend({ mode: "combo_frenzy", score: scoreRef.current, maxCombo: maxComboRef.current });
    flushSave();

    navigate(createPageUrl("GameOver") + `?score=${scoreRef.current}&combo=${maxComboRef.current}&mode=combo_frenzy`);
  };

  const handleZenQuit = () => {
    gameOverRef.current = true;
    cancelAnimationFrame(animRef.current);
    navigate(createPageUrl("Home"));
  };

  const themeColors = THEMES[theme] || THEMES.default;

  const modeLabel = isDuel ? "DUEL" : isSuddenDeath ? "SUDDEN DEATH" : isComboFrenzy ? "COMBO FRENZY" : isTimed ? "TIMED" : isEndless ? "ENDLESS" : isZen ? "ZEN" : null;
  const modeGradient = isDuel ? "from-rose-500 to-orange-400" : isSuddenDeath ? "from-red-600 to-rose-400" : isComboFrenzy ? "from-fuchsia-500 to-violet-400" : isTimed ? "from-rose-500 to-amber-400" : isEndless ? "from-orange-500 to-pink-500" : isZen ? "from-emerald-500 to-teal-400" : null;

  return (
    <div
      className="min-h-screen bg-[#0a0a0f] flex flex-col items-center justify-between py-10 px-6 select-none"
      onPointerDown={handleTap}
    >
      {/* Top HUD */}
      <div className="w-full max-w-sm">
        {modeLabel && (
          <div className="flex justify-center mb-3">
            <div className={`flex items-center gap-1.5 bg-gradient-to-r ${modeGradient} bg-clip-text text-transparent text-xs font-black tracking-widest`}>
              {isDuel ? <Users className="w-3.5 h-3.5 text-rose-400" /> : isSuddenDeath ? <Skull className="w-3.5 h-3.5 text-red-400" /> : isComboFrenzy ? <LinkIcon className="w-3.5 h-3.5 text-fuchsia-400" /> : isTimed ? <Timer className="w-3.5 h-3.5 text-amber-400" /> : isEndless ? <Repeat className="w-3.5 h-3.5 text-orange-400" /> : <Leaf className="w-3.5 h-3.5 text-emerald-400" />}
              {modeLabel} MODE
            </div>
          </div>
        )}
        <div className="flex items-start justify-between">
          {isZen ? (
            <div className="flex gap-4">
              <div className="text-center">
                <p className="text-emerald-400 text-2xl font-black">{zenPerfects}</p>
                <p className="text-white/30 text-[10px] tracking-widest">PERFECT</p>
              </div>
              <div className="text-center">
                <p className="text-cyan-400 text-2xl font-black">{zenGreats}</p>
                <p className="text-white/30 text-[10px] tracking-widest">GREAT</p>
              </div>
              <div className="text-center">
                <p className="text-white/50 text-2xl font-black">{zenTotal}</p>
                <p className="text-white/30 text-[10px] tracking-widest">TOTAL</p>
              </div>
            </div>
          ) : (
            <ScoreDisplay score={score} />
          )}
          {!isZen && <LivesDisplay lives={lives} />}
          {isTimed && (
            <div className="text-center">
              <p className={`text-2xl font-black tabular-nums ${timeLeft <= 10 ? "text-red-400 animate-pulse" : "text-amber-400"}`}>
                {Math.ceil(timeLeft)}s
              </p>
              <p className="text-white/30 text-[10px] tracking-widest">TIME</p>
            </div>
          )}
          {(isEndless || isComboFrenzy) && (
            <motion.button
              whileTap={{ scale: 0.9 }}
              onPointerDown={(e) => { e.stopPropagation(); isEndless ? handleEndlessQuit() : handleComboFrenzyQuit(); }}
              className="px-3 py-1.5 rounded-lg bg-white/5 border border-white/10 text-white/40 text-xs font-bold"
            >
              QUIT
            </motion.button>
          )}
          {isZen && (
            <motion.button
              whileTap={{ scale: 0.9 }}
              onPointerDown={(e) => { e.stopPropagation(); handleZenQuit(); }}
              className="px-3 py-1.5 rounded-lg bg-white/5 border border-white/10 text-white/40 text-xs font-bold"
            >
              EXIT
            </motion.button>
          )}
        </div>
      </div>

      {/* Center area */}
      <div className="flex-1 flex flex-col items-center justify-center w-full max-w-sm gap-8">
        <ComboDisplay combo={combo} />

        <div className="flex items-center gap-3 flex-wrap justify-center">
          {!isZen && !isTimed && !isComboFrenzy && (
            <div className="text-white/20 text-xs tracking-widest uppercase">
              {isSuddenDeath ? "Speed" : "Level"} {Math.min(20, Math.floor(((isSuddenDeath ? 0.9 : 1.2) - speedRef.current) / (isSuddenDeath ? 0.1 : 0.08)) + 1)}
            </div>
          )}
          {scoreMultiplier > 1 && !isZen && (
            <div className="flex items-center gap-1 bg-yellow-400/10 border border-yellow-400/20 rounded-full px-2 py-0.5">
              <span className="text-yellow-400 text-xs font-bold">{scoreMultiplier}× BOOST</span>
            </div>
          )}
          {activeChallenge && (
            <div className="flex items-center gap-1 bg-cyan-500/10 border border-cyan-500/20 rounded-full px-2 py-0.5">
              <span className="text-cyan-400 text-xs font-bold">{activeChallenge.icon} {activeChallenge.title}</span>
            </div>
          )}
          {isZen && (
            <div className="text-emerald-400/40 text-xs tracking-widest uppercase">
              Just breathe
            </div>
          )}
        </div>

        <TapBarMemo ref={tapBarRef} theme={themeColors} />

        <div className="h-16 flex items-center justify-center">
          <AnimatePresence mode="wait">
            {feedback && (
              <HitFeedback key={feedback.id} accuracy={feedback.accuracy} points={isZen ? null : feedback.points} />
            )}
          </AnimatePresence>
        </div>
      </div>

      {/* Bottom tap area */}
      <div className="w-full max-w-sm">
        <motion.div
          whileTap={{ scale: 0.96 }}
          className={`w-full py-7 rounded-2xl bg-gradient-to-r ${
            isDuel ? "from-rose-500 to-orange-400" : isSuddenDeath ? "from-red-600 to-rose-400" : isComboFrenzy ? "from-fuchsia-500 to-violet-400" : isTimed ? "from-rose-500 to-amber-400" : isZen ? "from-emerald-500 to-teal-400" : isEndless ? "from-orange-500 to-pink-500" : themeColors.bar
          } flex items-center justify-center shadow-xl`}
          style={{ boxShadow: isDuel ? "0 0 40px rgba(244,63,94,0.3)" : isSuddenDeath ? "0 0 40px rgba(220,38,38,0.3)" : isComboFrenzy ? "0 0 40px rgba(217,70,239,0.3)" : isTimed ? "0 0 40px rgba(244,63,94,0.3)" : isZen ? "0 0 40px rgba(16,185,129,0.3)" : isEndless ? "0 0 40px rgba(249,115,22,0.3)" : "0 0 40px rgba(139,92,246,0.3)" }}
        >
          <span className="text-white text-2xl font-black tracking-widest">TAP!</span>
        </motion.div>
        <p className="text-white/20 text-center text-xs mt-3 tracking-widest">Tap anywhere to play</p>
      </div>

      {/* Particle effects */}
      <ParticleExplosion trigger={particleTrigger} accuracy={particleAccuracy} />

      {/* Countdown overlay */}
      <AnimatePresence>
        {!started && countdown > 0 && (
          <motion.div
            key="countdown"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="absolute inset-0 bg-black/80 flex flex-col items-center justify-center z-50"
          >
            <motion.div
              key={countdown}
              initial={{ scale: 2, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              exit={{ scale: 0.5, opacity: 0 }}
              transition={{ duration: 0.3 }}
              className={`text-9xl font-black bg-gradient-to-r ${
                isSuddenDeath ? "from-red-400 to-rose-400" : isComboFrenzy ? "from-fuchsia-400 to-violet-400" : isTimed ? "from-rose-400 to-amber-400" : isZen ? "from-emerald-400 to-teal-400" : isEndless ? "from-orange-400 to-pink-400" : "from-violet-400 to-cyan-400"
              } bg-clip-text text-transparent`}
            >
              {countdown}
            </motion.div>
            <p className="text-white/40 mt-4 text-lg tracking-widest">
              {isSuddenDeath ? "ONE CHANCE" : isComboFrenzy ? "CHAIN IT UP" : isTimed ? "60 SECONDS" : isZen ? "RELAX" : isEndless ? "SURVIVE" : "GET READY"}
            </p>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Revive Modal */}
      <ReviveModal
        visible={showReviveModal}
        onRevive={handleRevive}
        onDecline={handleDeclineRevive}
        mode={gameMode}
      />
    </div>
  );
}