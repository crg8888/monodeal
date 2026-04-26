-- Slice 0: core RPCs.
-- - increment_counter(): atomic version bump for the T0.1 concurrency smoke test.
-- - reset_game(): wipes players + game_state to defaults (preserves settings).
-- - _assert_version() / _bump_version(): private helpers used by future RPCs.
--
-- Pattern (per docs/lovable-prompt-v5.md "Concurrency model"):
--   1. Read game_state via SELECT ... FOR UPDATE.
--   2. Assert caller's expected_version matches.
--   3. Mutate.
--   4. Bump version, set updated_at.
--   5. Return new state / version.

-- ============================================================================
-- increment_counter(): T0.1 smoke test target.
-- 200 concurrent calls from 2 tabs must yield final version = 200.
-- ============================================================================

create or replace function public.increment_counter()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  new_version int;
begin
  -- FOR UPDATE serializes concurrent calls on the singleton row.
  select version into new_version from game_state where id = 1 for update;
  new_version := new_version + 1;
  update game_state
    set version = new_version, updated_at = now()
    where id = 1;
  return new_version;
end;
$$;

revoke all on function public.increment_counter() from public;
grant execute on function public.increment_counter() to anon, authenticated;

-- ============================================================================
-- reset_game(): wipe players + most game_state fields. Preserves settings.
-- Usable from the host UI and from the T0.1 smoke test to seed v=0.
-- ============================================================================

create or replace function public.reset_game()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  new_version int;
begin
  select version into new_version from game_state where id = 1 for update;

  delete from players;

  update game_state set
    version = 0,
    phase = 'lobby',
    host_player_id = null,
    previous_phase = null,
    turn_player_id = null,
    turn_number = 0,
    plays_allowed_this_turn = 3,
    plays_this_turn = 0,
    has_drawn_this_turn = false,
    winner_player_id = null,
    deck_order = '{}',
    discard_pile = '{}',
    pending_stack = '[]'::jsonb,
    payment_queue = '[]'::jsonb,
    log = '[]'::jsonb,
    -- settings deliberately preserved
    started_at = null,
    updated_at = now()
  where id = 1;

  return 0;
end;
$$;

revoke all on function public.reset_game() from public;
grant execute on function public.reset_game() to anon, authenticated;

-- ============================================================================
-- Private helpers for future slices.
-- _assert_version raises 'stale_state' on mismatch; client retries once.
-- _bump_version is the standard tail of every mutating RPC.
-- ============================================================================

create or replace function public._assert_version(expected_version int)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_version int;
begin
  select version into current_version from game_state where id = 1 for update;
  if current_version != expected_version then
    raise exception 'stale_state'
      using detail = format('expected %s got %s', expected_version, current_version);
  end if;
end;
$$;

create or replace function public._bump_version()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  new_version int;
begin
  update game_state
    set version = version + 1, updated_at = now()
    where id = 1
    returning version into new_version;
  return new_version;
end;
$$;

revoke all on function public._assert_version(int) from public;
revoke all on function public._bump_version() from public;
-- Helpers are intentionally NOT granted to anon/authenticated.
-- They run from inside other security-definer RPCs only.
