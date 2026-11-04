import { createClientFromRequest } from 'npm:@base44/sdk@0.8.20';

// Score validation: check if a score is plausible given game mechanics
// Classic/Endless/SuddenDeath/ComboFrenzy: points per tap = max 100 * 6 (combo multiplier) = 600
// Timed: 60 seconds, minimum speed ~0.2s per tap = ~300 taps max → 300 * 600 = 180,000 theoretical max
// Realistic caps are much lower
const MODE_MAX_SCORES = {
  classic: 50000,
  endless: 50000,
  timed: 100000,
  sudden_death: 30000,
  combo_frenzy: 80000,
  duel: 50000,
};

const MAX_COMBO = 200;

Deno.serve(async (req) => {
  try {
    const base44 = createClientFromRequest(req);
    const user = await base44.auth.me();
    
    if (!user) {
      return Response.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const body = await req.json();
    const { mode, score, maxCombo, duelId, duelRole } = body;

    // Validate score bounds
    const maxAllowed = MODE_MAX_SCORES[mode] || 50000;
    if (typeof score !== 'number' || score < 0 || score > maxAllowed) {
      return Response.json({ error: 'Invalid score' }, { status: 400 });
    }
    if (typeof maxCombo !== 'number' || maxCombo < 0 || maxCombo > MAX_COMBO) {
      return Response.json({ error: 'Invalid combo' }, { status: 400 });
    }

    const validatedScore = Math.floor(score);
    const validatedCombo = Math.floor(maxCombo);

    // Get player profile
    const profiles = await base44.asServiceRole.entities.PlayerProfile.filter({ created_by: user.email });
    if (profiles.length === 0) {
      return Response.json({ error: 'No profile found' }, { status: 404 });
    }
    const profile = profiles[0];

    // Handle duel score submission
    if (mode === "duel" && duelId && duelRole) {
      const duels = await base44.asServiceRole.entities.duel.filter({ id: duelId });
      if (duels.length === 0) {
        return Response.json({ error: 'Duel not found' }, { status: 404 });
      }
      const duel = duels[0];

      // Verify this user is actually part of this duel
      if (duelRole === "host" && duel.host_id !== profile.id) {
        return Response.json({ error: 'Not authorized for this duel' }, { status: 403 });
      }
      if (duelRole === "guest" && duel.guest_id !== profile.id) {
        return Response.json({ error: 'Not authorized for this duel' }, { status: 403 });
      }

      // Prevent double submission
      if (duelRole === "host" && duel.host_score >= 0) {
        return Response.json({ error: 'Score already submitted' }, { status: 409 });
      }
      if (duelRole === "guest" && duel.guest_score >= 0) {
        return Response.json({ error: 'Score already submitted' }, { status: 409 });
      }

      const updateData = duelRole === "host"
        ? { host_score: validatedScore, host_combo: validatedCombo }
        : { guest_score: validatedScore, guest_combo: validatedCombo };

      // Check if opponent already submitted
      const otherDone = duelRole === "host" ? duel.guest_score >= 0 : duel.host_score >= 0;
      if (otherDone) updateData.status = "completed";

      await base44.asServiceRole.entities.duel.update(duelId, updateData);
      return Response.json({ success: true, validated_score: validatedScore });
    }

    // Handle solo mode: update best scores on profile
    const bestField = {
      classic: 'best_classic',
      endless: 'best_endless',
      timed: 'best_timed',
      sudden_death: 'best_sudden',
      combo_frenzy: 'best_combofrenzy',
    }[mode];

    if (bestField && validatedScore > (profile[bestField] || 0)) {
      await base44.asServiceRole.entities.PlayerProfile.update(profile.id, {
        [bestField]: validatedScore,
      });
    }

    return Response.json({ success: true, validated_score: validatedScore });
  } catch (error) {
    return Response.json({ error: error.message }, { status: 500 });
  }
});