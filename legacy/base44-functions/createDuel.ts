import { createClientFromRequest } from 'npm:@base44/sdk@0.8.20';

Deno.serve(async (req) => {
  try {
    const base44 = createClientFromRequest(req);
    const user = await base44.auth.me();
    
    if (!user) {
      return Response.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const body = await req.json();
    const { code, host_name } = body;

    if (!code || !host_name) {
      return Response.json({ error: 'Missing code or host_name' }, { status: 400 });
    }

    // Rate limit: check how many duels this user created in the last 5 minutes
    const recentDuels = await base44.asServiceRole.entities.duel.filter({ created_by: user.email });
    const now = Date.now();
    const RATE_LIMIT_WINDOW_MS = 5 * 60 * 1000; // 5 minutes
    const MAX_DUELS_PER_WINDOW = 5;

    const recentCount = recentDuels.filter(d => {
      const created = new Date(d.created_date).getTime();
      return now - created < RATE_LIMIT_WINDOW_MS;
    }).length;

    if (recentCount >= MAX_DUELS_PER_WINDOW) {
      return Response.json({ error: 'Rate limited. Wait a few minutes before creating more duels.' }, { status: 429 });
    }

    // Also clean up any old waiting duels by this user (max 1 active waiting duel)
    const myWaiting = recentDuels.filter(d => d.status === "waiting");
    for (const old of myWaiting) {
      await base44.asServiceRole.entities.duel.delete(old.id);
    }

    // Get player profile ID
    const profiles = await base44.asServiceRole.entities.PlayerProfile.filter({ created_by: user.email });
    const profileId = profiles.length > 0 ? profiles[0].id : null;

    const created = await base44.asServiceRole.entities.duel.create({
      code,
      host_id: profileId,
      host_name: host_name.trim().slice(0, 20),
      status: "waiting",
      host_score: -1,
      host_combo: 0,
      guest_score: -1,
      guest_combo: 0,
      guest_joined: false,
    });

    return Response.json({ id: created.id, code });
  } catch (error) {
    return Response.json({ error: error.message }, { status: 500 });
  }
});