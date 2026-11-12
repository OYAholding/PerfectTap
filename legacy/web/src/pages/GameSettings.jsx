import React, { useState, useEffect } from "react";
import { createPageUrl } from "@/utils";
import { Link } from "react-router-dom";
import { motion } from "framer-motion";
import { ArrowLeft, Volume2, VolumeX, Vibrate, RotateCcw, Music, Trash2, AlertTriangle } from "lucide-react";
import { startBgMusic, stopBgMusic } from "@/components/game/soundEngine";
import { getCachedProfile, getProfileId, quickSave, flushSave } from "@/components/game/playerService";
import { base44 } from "@/api/base44Client";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";

export default function GameSettings() {
  const [soundOn, setSoundOn] = useState(true);
  const [musicOn, setMusicOn] = useState(true);
  const [vibrationOn, setVibrationOn] = useState(true);

  useEffect(() => {
    const p = getCachedProfile();
    setSoundOn(p?.sound_enabled !== false);
    setMusicOn(p?.music_enabled !== false);
    setVibrationOn(p?.haptics_enabled !== false);
    // Keep localStorage in sync for sound engine
    if (p?.sound_enabled === false) localStorage.setItem("perfecttap_sound", "false");
    if (p?.music_enabled === false) localStorage.setItem("perfecttap_music", "false");
  }, []);

  const toggleSound = () => {
    const next = !soundOn;
    setSoundOn(next);
    localStorage.setItem("perfecttap_sound", next.toString());
    quickSave({ sound_enabled: next });
  };

  const toggleMusic = () => {
    const next = !musicOn;
    setMusicOn(next);
    localStorage.setItem("perfecttap_music", next.toString());
    quickSave({ music_enabled: next });
    if (next) startBgMusic(); else stopBgMusic();
  };

  const toggleVibration = () => {
    const next = !vibrationOn;
    setVibrationOn(next);
    quickSave({ haptics_enabled: next });
  };

  const resetScores = async () => {
    if (window.confirm("Reset all scores and progress?")) {
      quickSave({
        coins: 0, best_classic: 0, best_endless: 0, best_timed: 0, best_sudden: 0,
        best_combofrenzy: 0, score_history: [], stats: {}, owned_items: [],
        equipped: {}, challenges_done: [], active_challenge: "", daily_rewards: {},
        quest_data: {}, boost: {}, theme: "default", achievements: [],
        season_pass: {}, lucky_wheel: {}, recent_matches: [], xp: 0, level: 1,
      });
      await flushSave();
      localStorage.removeItem("perfecttap_profile_cache");
      window.location.reload();
    }
  };

  return (
    <div className="min-h-screen bg-[#0a0a0f] flex flex-col px-6 py-10">
      <div className="max-w-sm mx-auto w-full">
        {/* Header */}
        <div className="flex items-center gap-4 mb-10">
          <Link to={createPageUrl("Home")}>
            <motion.button
              whileTap={{ scale: 0.9 }}
              className="w-10 h-10 rounded-xl bg-white/5 border border-white/10 flex items-center justify-center text-white/60"
            >
              <ArrowLeft className="w-5 h-5" />
            </motion.button>
          </Link>
          <div>
            <h1 className="text-2xl font-black text-white">SETTINGS</h1>
          </div>
        </div>

        {/* Settings List */}
        <div className="flex flex-col gap-3">
          <SettingRow
            icon={soundOn ? <Volume2 className="w-5 h-5" /> : <VolumeX className="w-5 h-5" />}
            label="Sound Effects"
            description={soundOn ? "On" : "Off"}
            active={soundOn}
            onToggle={toggleSound}
            delay={0}
          />
          <SettingRow
            icon={<Music className="w-5 h-5" />}
            label="Background Music"
            description={musicOn ? "On" : "Off"}
            active={musicOn}
            onToggle={toggleMusic}
            delay={0.05}
          />
          <SettingRow
            icon={<Vibrate className="w-5 h-5" />}
            label="Haptic Feedback"
            description={vibrationOn ? "On" : "Off"}
            active={vibrationOn}
            onToggle={toggleVibration}
            delay={0.1}
          />
        </div>

        {/* Danger Zone */}
        <div className="mt-10">
          <p className="text-white/20 text-xs tracking-widest uppercase mb-3">Danger Zone</p>
          <div className="flex flex-col gap-3">
            <motion.button
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.15 }}
              whileTap={{ scale: 0.97 }}
              onClick={resetScores}
              className="w-full py-4 rounded-xl bg-red-500/10 border border-red-500/20 text-red-400 font-semibold flex items-center justify-center gap-2"
            >
              <RotateCcw className="w-4 h-4" />
              Reset All Progress
            </motion.button>

            <DeleteAccountButton />
          </div>
        </div>

        {/* About */}
        <div className="mt-10 text-center">
          <p className="text-white/20 text-xs">Perfect Tap v1.0</p>
          <p className="text-white/10 text-xs mt-1">Test your precision</p>
        </div>
      </div>
    </div>
  );
}

function DeleteAccountButton() {
  const [deleting, setDeleting] = useState(false);

  const handleDelete = async () => {
    setDeleting(true);
    const profileId = getProfileId();
    if (profileId) {
      await base44.entities.PlayerProfile.delete(profileId);
    }
    localStorage.clear();
    base44.auth.logout("/");
  };

  return (
    <AlertDialog>
      <AlertDialogTrigger asChild>
        <motion.button
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2 }}
          whileTap={{ scale: 0.97 }}
          className="w-full py-4 rounded-xl bg-red-600/10 border border-red-600/30 text-red-500 font-semibold flex items-center justify-center gap-2"
        >
          <Trash2 className="w-4 h-4" />
          Delete Account
        </motion.button>
      </AlertDialogTrigger>
      <AlertDialogContent className="bg-[#15151f] border border-white/10 max-w-xs mx-auto">
        <AlertDialogHeader>
          <div className="flex justify-center mb-2">
            <div className="w-12 h-12 rounded-full bg-red-500/20 flex items-center justify-center">
              <AlertTriangle className="w-6 h-6 text-red-400" />
            </div>
          </div>
          <AlertDialogTitle className="text-white text-center">Delete Account?</AlertDialogTitle>
          <AlertDialogDescription className="text-white/50 text-center text-sm">
            This will permanently delete your profile, scores, coins, and all progress. This action cannot be undone.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter className="flex gap-2 sm:justify-center">
          <AlertDialogCancel className="flex-1 bg-white/5 border-white/10 text-white hover:bg-white/10 hover:text-white">
            Cancel
          </AlertDialogCancel>
          <AlertDialogAction
            onClick={handleDelete}
            disabled={deleting}
            className="flex-1 bg-red-600 hover:bg-red-700 text-white border-0"
          >
            {deleting ? "Deleting…" : "Delete Forever"}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}

function SettingRow({ icon, label, description, active, onToggle, delay }) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay }}
      onClick={onToggle}
      className="flex items-center gap-4 bg-white/5 border border-white/10 rounded-2xl p-4 cursor-pointer hover:bg-white/8 transition-all"
    >
      <div className={`w-10 h-10 rounded-xl flex items-center justify-center ${active ? "bg-violet-500/20 text-violet-400" : "bg-white/5 text-white/30"}`}>
        {icon}
      </div>
      <div className="flex-1">
        <p className="text-white font-semibold">{label}</p>
        <p className="text-white/30 text-sm">{description}</p>
      </div>
      {/* Toggle */}
      <div className={`w-12 h-6 rounded-full transition-all ${active ? "bg-violet-500" : "bg-white/10"}`}>
        <motion.div
          animate={{ x: active ? 24 : 2 }}
          transition={{ type: "spring", stiffness: 500, damping: 30 }}
          className="w-5 h-5 rounded-full bg-white mt-0.5"
        />
      </div>
    </motion.div>
  );
}