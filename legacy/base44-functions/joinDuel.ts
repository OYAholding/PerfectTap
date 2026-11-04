import { createClientFromRequest } from 'npm:@base44/sdk@0.8.20';

Deno.serve(async (req) => {
  try {
    const base44 = createClientFromRequest(req);
    const user = await base44.auth.me();
    
    if (!user) {
      return Response.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const body = await req.json();
    const { code, guest_name } = body;

    if (!code || !guest_name) {
      return Response.json({ error: 'Missing code or guest_name' }, { status: 400 });
    }

    // Find duel by code
    const duels = await base44.asServiceRole.entities.duel.filter({ code: code.trim().toUpperCase() });
    if (duels.length === 0) {
      return Response.json({ error: 'Code not found. Check and try again.' }, { status: 404 });
    }

    const duel = duels[0];

    // Validate duel is joinable
    if (duel.status !== "waiting") {
      return Response.json({ error: 'This duel is no longer available.' }, { status: 409 });
    }

    if (duel.guest_joined) {
      return Response.json({ error: 'This duel already has two players.' }, { status: 409 });
    }

    // Get the joining player's profile
    const profiles = await base44.asServiceRole.entities.PlayerProfile.filter({ created_by: user.email });
    if (profiles.length === 0) {
      return Response.json({ error: 'No profile found' }, { status: 404 });
    }
    const profile = profiles[0];

    // Prevent host from joining their own duel
    if (duel.host_id === profile.id) {
      return Response.json({ error: 'You cannot join your own duel.' }, { status: 400 });
    }

    // Update the duel with validated data
    await base44.asServiceRole.entities.duel.update(duel.id, {
      guest_id: profile.id,
      guest_name: guest_name.trim().slice(0, 20),
      guest_joined: true,
      status: "in_progress",
    });

    return Response.json({ 
      success: true, 
      duelId: duel.id,
      hostName: duel.host_name 
    });
  } catch (error) {
    return Response.json({ error: error.message }, { status: 500 });
  }
});