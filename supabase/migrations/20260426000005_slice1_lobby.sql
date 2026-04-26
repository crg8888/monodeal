-- Slice 1: lobby + reconnect.
-- RPCs: join_lobby, reconnect, kick_player_lobby, host_full_reset.
-- Helpers: _validate_token, _append_log.
--
-- All mutating RPCs follow the spec's concurrency pattern:
--   1. Lock game_state singleton row with FOR UPDATE.
--   2. Validate caller's player_token against players.token.
--   3. Mutate.
--   4. Bump version + updated_at, append log.

-- ============================================================================
-- Helpers (private; not granted to anon)
-- ============================================================================

create or replace function public._validate_token(p_player_id uuid, p_player_token uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not exists (
    select 1 from players where id = p_player_id and token = p_player_token
  ) then
    raise exception 'auth_failed';
  end if;
end;
$$;
revoke all on function public._validate_token(uuid, uuid) from public;

create or replace function public._append_log(p_kind text, p_text text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  update game_state
    set log = log || jsonb_build_array(
      jsonb_build_object('at', now()::text, 'kind', p_kind, 'text', p_text)
    )
    where id = 1;
end;
$$;
revoke all on function public._append_log(text, text) from public;

-- ============================================================================
-- join_lobby(name) → { player_id, player_token, assigned_name, is_host }
-- Auto-suffixes duplicate names: "Chintan", "Chintan (2)", "Chintan (3)".
-- First joiner becomes host. Lobby caps at settings.max_players (default 5).
-- ============================================================================

create or replace function public.join_lobby(p_name text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_phase text;
  v_max_players int;
  v_current_count int;
  v_seat int;
  v_name text;
  v_suffix int := 1;
  v_candidate text;
  v_player_id uuid := gen_random_uuid();
  v_player_token uuid := gen_random_uuid();
  v_is_host bool := false;
  v_host_id uuid;
begin
  v_name := nullif(trim(p_name), '');
  if v_name is null then raise exception 'name_required'; end if;
  if length(v_name) > 30 then raise exception 'name_too_long'; end if;

  perform 1 from game_state where id = 1 for update;
  select phase, (settings->>'max_players')::int, host_player_id
    into v_phase, v_max_players, v_host_id
    from game_state where id = 1;

  if v_phase != 'lobby' then
    raise exception 'lobby_closed' using detail = format('phase=%s', v_phase);
  end if;

  select count(*) into v_current_count from players;
  if v_current_count >= v_max_players then
    raise exception 'lobby_full';
  end if;

  -- Auto-suffix duplicates (case-insensitive match).
  v_candidate := v_name;
  while exists (select 1 from players where lower(name) = lower(v_candidate)) loop
    v_suffix := v_suffix + 1;
    v_candidate := v_name || ' (' || v_suffix || ')';
  end loop;
  v_name := v_candidate;

  select coalesce(max(seat_index), -1) + 1 into v_seat from players;

  insert into players (id, token, name, seat_index)
  values (v_player_id, v_player_token, v_name, v_seat);

  if v_host_id is null then
    update game_state set host_player_id = v_player_id where id = 1;
    v_is_host := true;
  end if;

  perform _append_log('join', v_name || (case when v_is_host then ' joined (host)' else ' joined' end));

  update game_state set version = version + 1, updated_at = now() where id = 1;

  return jsonb_build_object(
    'player_id', v_player_id,
    'player_token', v_player_token,
    'assigned_name', v_name,
    'is_host', v_is_host
  );
end;
$$;
revoke all on function public.join_lobby(text) from public;
grant execute on function public.join_lobby(text) to anon, authenticated;

-- ============================================================================
-- reconnect(player_id, player_token) → { ok, phase } | { ok: false, reason }
-- Fast path: already-known player refreshes / reopens tab. Validates token,
-- marks is_connected=true, returns the current phase so client routes correctly.
-- ============================================================================

create or replace function public.reconnect(p_player_id uuid, p_player_token uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_match bool;
  v_phase text;
begin
  perform 1 from game_state where id = 1 for update;
  select exists(
    select 1 from players where id = p_player_id and token = p_player_token
  ) into v_match;

  if not v_match then
    return jsonb_build_object('ok', false, 'reason', 'token_invalid');
  end if;

  update players set is_connected = true, last_seen_at = now()
    where id = p_player_id;
  select phase into v_phase from game_state where id = 1;
  update game_state set version = version + 1, updated_at = now() where id = 1;

  return jsonb_build_object('ok', true, 'phase', v_phase);
end;
$$;
revoke all on function public.reconnect(uuid, uuid) from public;
grant execute on function public.reconnect(uuid, uuid) to anon, authenticated;

-- ============================================================================
-- kick_player_lobby — host removes a player BEFORE game start.
-- Mid-game kicks land in Slice 9 (different RPC because they have to handle
-- moving the player's hand+bank+items to discard).
-- ============================================================================

create or replace function public.kick_player_lobby(
  p_actor_id uuid, p_actor_token uuid, p_target_id uuid
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_phase text;
  v_host_id uuid;
  v_target_name text;
begin
  perform 1 from game_state where id = 1 for update;
  perform _validate_token(p_actor_id, p_actor_token);
  select phase, host_player_id into v_phase, v_host_id from game_state where id = 1;
  if p_actor_id != v_host_id then raise exception 'not_host'; end if;
  if v_phase != 'lobby' then
    raise exception 'wrong_phase' using detail = v_phase;
  end if;
  select name into v_target_name from players where id = p_target_id;
  if v_target_name is null then raise exception 'target_not_found'; end if;

  delete from players where id = p_target_id;

  -- Compact seat indexes (no gaps after removal).
  with ordered as (
    select id, row_number() over (order by seat_index) - 1 as new_seat
    from players
  )
  update players p set seat_index = o.new_seat::int
    from ordered o where p.id = o.id;

  perform _append_log('kick', v_target_name || ' was kicked');
  update game_state set version = version + 1, updated_at = now() where id = 1;

  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function public.kick_player_lobby(uuid, uuid, uuid) from public;
grant execute on function public.kick_player_lobby(uuid, uuid, uuid) to anon, authenticated;

-- ============================================================================
-- host_full_reset — host wipes everything to defaults.
-- This is the auth'd version of reset_game (which stays anon-callable as the
-- emergency escape hatch / dev smoke test).
-- ============================================================================

create or replace function public.host_full_reset(
  p_actor_id uuid, p_actor_token uuid
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_host_id uuid;
begin
  perform 1 from game_state where id = 1 for update;
  perform _validate_token(p_actor_id, p_actor_token);
  select host_player_id into v_host_id from game_state where id = 1;
  if p_actor_id != v_host_id then raise exception 'not_host'; end if;

  delete from players where true;

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
    log = jsonb_build_array(
      jsonb_build_object('at', now()::text, 'kind', 'reset', 'text', 'host triggered full reset')
    ),
    started_at = null,
    updated_at = now()
  where id = 1;

  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function public.host_full_reset(uuid, uuid) from public;
grant execute on function public.host_full_reset(uuid, uuid) to anon, authenticated;
