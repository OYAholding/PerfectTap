-- pgTAP: season calendar rule shared with iOS (SeasonCalendar).
-- Run: supabase test db --local
--
-- The date → id table and the claim-window table below are mirrored
-- one-to-one by ios/PerfectTap/PerfectTapTests/EconomyServiceTests.swift
-- (SeasonCalendarAlignmentTests). Change both together.
begin;
create extension if not exists pgtap with schema extensions;
do $$
declare s text;
begin
  select n.nspname into s from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pgtap';
  perform set_config('search_path', 'public, ' || quote_ident(coalesce(s, 'extensions')), false);
end $$;
select plan(33);

create function pg_temp.cfg() returns jsonb language sql as $$
  select config from private.economy_configs where version = 'balanced-premium-rc1'
$$;
create function pg_temp.season(t timestamptz) returns text language sql as $$
  select season_id || ' ' || to_char(starts_at at time zone 'utc', 'YYYY-MM-DD') || ' '
         || to_char(ends_at at time zone 'utc', 'YYYY-MM-DD')
  from private.season_at(pg_temp.cfg(), t)
$$;
create function pg_temp.verdict(season_id text, tier int, t timestamptz) returns text language sql as $$
  select coalesce(private.season_tier_verdict(pg_temp.cfg(), season_id, tier, t), 'ok')
$$;

-- Config shape (inactive, rule instead of a single placeholder season).
select ok(not (select active from private.economy_configs where version = 'balanced-premium-rc1'),
  'rc1 stays inactive');
select ok(not pg_temp.cfg() ? 'active_season', 'placeholder active_season removed');
select is(pg_temp.cfg()->'season_calendar',
  '{"anchor":"2026-03-01","length_months":3,"id_format":"season_<n>","tiers":30,"max_tiers_per_day":15,"grace_hours":72}'::jsonb,
  'season_calendar rule pinned (mirrors EconomyConfig.SeasonCalendarRule.balancedPremiumRC1)');
select ok(not has_function_privilege('authenticated', 'private.season_tier_verdict(jsonb,text,bigint,timestamptz)', 'EXECUTE')
  and not has_function_privilege('anon', 'private.season_at(jsonb,timestamptz)', 'EXECUTE'),
  'calendar helpers are internal');

-- Shared table: date (UTC) → "id start end(exclusive)".
select is(pg_temp.season('2026-03-01T00:00:00Z'), 'season_1 2026-03-01 2026-06-01', 'anchor instant is season_1');
select is(pg_temp.season('2026-05-31T23:59:59Z'), 'season_1 2026-03-01 2026-06-01', 'last second of season_1');
select is(pg_temp.season('2026-06-01T00:00:00Z'), 'season_2 2026-06-01 2026-09-01', 'season_2 starts Jun 1');
select is(pg_temp.season('2026-11-26T12:00:00Z'), 'season_3 2026-09-01 2026-12-01', 'today (2026-11-26) is season_3');
select is(pg_temp.season('2026-11-30T23:59:59Z'), 'season_3 2026-09-01 2026-12-01', 'boundary: Nov 30 23:59:59 is still season_3');
select is(pg_temp.season('2026-12-01T00:00:00Z'), 'season_4 2026-12-01 2027-03-01', 'boundary: Dec 1 00:00 starts season_4');
select is(pg_temp.season('2027-02-28T23:59:59Z'), 'season_4 2026-12-01 2027-03-01', 'last second of season_4');
select is(pg_temp.season('2027-03-01T00:00:00Z'), 'season_5 2027-03-01 2027-06-01', 'season_5 starts Mar 1 2027');
select is(pg_temp.season('2028-02-29T12:00:00Z'), 'season_8 2027-12-01 2028-03-01', 'leap day 2028 is season_8');
select is(pg_temp.season('2026-02-28T23:59:59Z'), null, 'no season before the anchor');
select is(pg_temp.season('2026-12-01T03:00:00+05:00'), 'season_3 2026-09-01 2026-12-01',
  'computed in UTC, not the session/offset time zone');

-- Shared table: claim window (season_id, instant) → verdict, tier 1.
select is(pg_temp.verdict('season_3', 1, '2026-11-26T12:00:00Z'), 'ok', 'current season accepted');
select is(pg_temp.verdict('season_3', 1, '2026-12-01T00:00:00Z'), 'ok', 'grace: previous season right after the boundary');
select is(pg_temp.verdict('season_3', 1, '2026-12-03T23:59:59Z'), 'ok', 'grace: previous season at 72h - 1s');
select is(pg_temp.verdict('season_3', 1, '2026-12-04T00:00:00Z'), 'invalid_payload', 'grace over: previous season refused at 72h');
select is(pg_temp.verdict('season_4', 1, '2026-11-30T23:59:59Z'), 'invalid_payload', 'next season refused before it starts');
select is(pg_temp.verdict('season_4', 1, '2026-12-01T00:00:00Z'), 'ok', 'new season accepted from its first instant');
select is(pg_temp.verdict('season_2', 1, '2026-11-26T12:00:00Z'), 'invalid_payload', 'older season refused');
select is(pg_temp.verdict('season_2', 1, '2026-09-02T00:00:00Z'), 'ok', 'season_2 inside its own grace window');
select is(pg_temp.verdict('season_1_neon_nights', 1, '2026-12-15T00:00:00Z'), 'invalid_payload',
  'old placeholder id refused');

-- Tier bound and per-day pace (max_tiers_per_day × days since that season began).
select is(pg_temp.verdict('season_4', 15, '2026-12-01T10:00:00Z'), 'ok', 'pace: 15 tiers on day 1');
select is(pg_temp.verdict('season_4', 16, '2026-12-01T10:00:00Z'), 'implausible_result', 'pace: 16 tiers on day 1 refused');
select is(pg_temp.verdict('season_4', 16, '2026-12-02T00:00:00Z'), 'ok', 'pace: 16 tiers on day 2');
select is(pg_temp.verdict('season_3', 30, '2026-12-02T00:00:00Z'), 'ok', 'grace claim paced from the previous season start');
select is(pg_temp.verdict('season_3', 31, '2026-11-26T12:00:00Z'), 'invalid_payload', 'tier above tiers refused');

-- Owner-tunable: grace_hours and the calendar itself are config values.
update private.economy_configs set config = jsonb_set(config, '{season_calendar,grace_hours}', '24')
where version = 'balanced-premium-rc1';
select is(pg_temp.verdict('season_3', 1, '2026-12-01T23:59:59Z'), 'ok', 'grace_hours=24: inside');
select is(pg_temp.verdict('season_3', 1, '2026-12-02T00:00:00Z'), 'invalid_payload', 'grace_hours=24: outside');
update private.economy_configs set config = jsonb_set(config, '{season_calendar,length_months}', '1')
where version = 'balanced-premium-rc1';
select is(pg_temp.season('2026-11-26T12:00:00Z'), 'season_9 2026-11-01 2026-12-01', 'length_months=1 → monthly seasons');
update private.economy_configs set config = jsonb_set(config, '{season_calendar,anchor}', '"2026-03-15"')
where version = 'balanced-premium-rc1';
select is(pg_temp.verdict('season_9', 1, '2026-11-26T12:00:00Z'), 'invalid_payload',
  'malformed calendar (anchor not the 1st) fails closed');

select * from finish();
rollback;
