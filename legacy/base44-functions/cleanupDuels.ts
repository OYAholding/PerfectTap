import { createClientFromRequest } from 'npm:@base44/sdk@0.8.20';

Deno.serve(async (req) => {
  try {
    const base44 = createClientFromRequest(req);
    const user = await base44.auth.me();
    
    if (user?.role !== 'admin') {
      return Response.json({ error: 'Forbidden: Admin access required' }, { status: 403 });
    }

    // Find all waiting duels
    const waitingDuels = await base44.asServiceRole.entities.duel.filter({ status: "waiting" });
    
    const now = Date.now();
    const MAX_AGE_MS = 10 * 60 * 1000; // 10 minutes
    let cleaned = 0;

    for (const duel of waitingDuels) {
      const created = new Date(duel.created_date).getTime();
      if (now - created > MAX_AGE_MS) {
        await base44.asServiceRole.entities.duel.delete(duel.id);
        cleaned++;
      }
    }

    // Also clean completed duels older than 24 hours
    const completedDuels = await base44.asServiceRole.entities.duel.filter({ status: "completed" });
    const MAX_COMPLETED_AGE_MS = 24 * 60 * 60 * 1000; // 24 hours
    let cleanedCompleted = 0;

    for (const duel of completedDuels) {
      const created = new Date(duel.created_date).getTime();
      if (now - created > MAX_COMPLETED_AGE_MS) {
        await base44.asServiceRole.entities.duel.delete(duel.id);
        cleanedCompleted++;
      }
    }

    return Response.json({ 
      cleaned_waiting: cleaned, 
      cleaned_completed: cleanedCompleted,
      total: cleaned + cleanedCompleted
    });
  } catch (error) {
    return Response.json({ error: error.message }, { status: 500 });
  }
});