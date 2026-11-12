// Centralized sound engine for Perfect Tap
// All sounds are generated via Web Audio API (no files needed)

let bgMusicCtx = null;
let bgMusicTimeouts = [];
let bgMusicPlaying = false;

// Shared SFX context — reused to avoid browser AudioContext limit (~6)
let sfxCtx = null;
function getSfxCtx() {
  if (!sfxCtx || sfxCtx.state === "closed") {
    sfxCtx = new (window.AudioContext || window.webkitAudioContext)();
  }
  // Resume if suspended (autoplay policy)
  if (sfxCtx.state === "suspended") sfxCtx.resume();
  return sfxCtx;
}

function getCtx() {
  return new (window.AudioContext || window.webkitAudioContext)();
}

export function playSfx(type) {
  if (localStorage.getItem("perfecttap_sound") === "false") return;
  try {
    const ctx = getSfxCtx();
    const configs = {
      perfect:   [{ freq: 880, wt: "sine", dur: 0.18 }, { freq: 1100, wt: "sine", dur: 0.12, delay: 0.06 }],
      great:     [{ freq: 660, wt: "sine", dur: 0.15 }],
      good:      [{ freq: 440, wt: "sine", dur: 0.12 }],
      miss:      [{ freq: 180, wt: "sawtooth", dur: 0.22 }],
      comboBreak:[{ freq: 220, wt: "sawtooth", dur: 0.15 }, { freq: 150, wt: "sawtooth", dur: 0.2, delay: 0.08 }],
      comboMilestone: [{ freq: 660, wt: "sine", dur: 0.1 }, { freq: 880, wt: "sine", dur: 0.1, delay: 0.1 }, { freq: 1100, wt: "sine", dur: 0.15, delay: 0.2 }],
      challengeComplete: [{ freq: 523, wt: "sine", dur: 0.12 }, { freq: 659, wt: "sine", dur: 0.12, delay: 0.12 }, { freq: 784, wt: "sine", dur: 0.12, delay: 0.24 }, { freq: 1047, wt: "sine", dur: 0.3, delay: 0.36 }],
      dailyReward: [{ freq: 440, wt: "sine", dur: 0.1 }, { freq: 550, wt: "sine", dur: 0.1, delay: 0.1 }, { freq: 660, wt: "sine", dur: 0.1, delay: 0.2 }, { freq: 880, wt: "sine", dur: 0.25, delay: 0.3 }],
      countdown: [{ freq: 330, wt: "sine", dur: 0.1 }],
      countdownGo: [{ freq: 880, wt: "sine", dur: 0.2 }],
    };
    const notes = configs[type];
    if (!notes) return;
    notes.forEach(({ freq, wt, dur, delay = 0 }) => {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.frequency.value = freq;
      osc.type = wt;
      const startAt = ctx.currentTime + delay;
      gain.gain.setValueAtTime(0.18, startAt);
      gain.gain.exponentialRampToValueAtTime(0.001, startAt + dur);
      osc.start(startAt);
      osc.stop(startAt + dur + 0.01);
    });
  } catch (e) {}
}

// Background music: looping ambient synth pattern
export function startBgMusic() {
  if (localStorage.getItem("perfecttap_music") === "false") return;
  if (bgMusicPlaying) return;
  try {
    bgMusicCtx = getCtx();
    bgMusicPlaying = true;
    scheduleBgLoop();
  } catch (e) {}
}

function scheduleBgLoop() {
  if (!bgMusicPlaying || !bgMusicCtx) return;
  const ctx = bgMusicCtx;
  const beatDur = 60 / 90; // 90 BPM
  const totalBeats = 16;

  // Bass
  const bassNotes = [55, 55, 65, 55, 55, 65, 73, 65];
  bassNotes.forEach((freq, i) => {
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.connect(gain); gain.connect(ctx.destination);
    osc.type = "triangle"; osc.frequency.value = freq;
    const t = ctx.currentTime + i * beatDur * 2;
    gain.gain.setValueAtTime(0, t);
    gain.gain.linearRampToValueAtTime(0.05, t + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.001, t + beatDur * 1.8);
    osc.start(t); osc.stop(t + beatDur * 2);
  });

  // Melody
  const melody = [220, 0, 261, 0, 220, 246, 0, 220, 0, 261, 293, 0, 261, 246, 0, 0];
  melody.forEach((freq, i) => {
    if (!freq) return;
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.connect(gain); gain.connect(ctx.destination);
    osc.type = "sine"; osc.frequency.value = freq;
    const t = ctx.currentTime + i * beatDur;
    gain.gain.setValueAtTime(0, t);
    gain.gain.linearRampToValueAtTime(0.035, t + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.001, t + beatDur * 0.8);
    osc.start(t); osc.stop(t + beatDur);
  });

  const loopDuration = totalBeats * beatDur * 1000 - 80;
  const tid = setTimeout(() => {
    if (bgMusicPlaying) scheduleBgLoop();
  }, loopDuration);
  bgMusicTimeouts.push(tid);
}

export function stopBgMusic() {
  bgMusicPlaying = false;
  bgMusicTimeouts.forEach(t => clearTimeout(t));
  bgMusicTimeouts = [];
  if (bgMusicCtx) {
    try { bgMusicCtx.close(); } catch (e) {}
    bgMusicCtx = null;
  }
}

export function isBgMusicEnabled() {
  return localStorage.getItem("perfecttap_music") !== "false";
}