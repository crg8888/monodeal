-- Slice 9: polish — host controls + restart cycle.
-- - host_force_end_turn: advance an AFK turn player.
-- - reset_to_lobby: keep players, reset game state to character_select.
-- - host_kick_mid_game: remove a player mid-game (their cards go to discard).

-- ============================================================================
-- host_force_end_turn — clears any pending state for the active turn player
-- and advances the turn. Active payment debts are auto-forgiven (Slice 9
-- simplification — full force-auto-pay can ship later).
-- ============================================================================

create or replace function public.host_force_end_turn(
  p_actor_id uuid, p_actor_token uuid
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_host_id uuid;
  v_phase text;
  v_turn_id uuid;
  v_hand uuid[];
  v_excess int;
  v_discard_some uuid[];
begin
  perform 1 from game_state where id = 1 for update;
  perform _validate_token(p_actor_id, p_actor_token);
  select host_player_id, phase, turn_player_id into v_host_id, v_phase, v_turn_id
    from game_state where id = 1;
  if p_actor_id != v_host_id then raise exception 'not_host'; end if;
  if v_phase != 'in_game' then raise exception 'wrong_phase' using detail = v_phase; end if;
  if v_turn_id is null then raise exception 'no_active_turn'; end if;

  -- Auto-discard down to 7 (newest cards first — pop from end).
  select hand into v_hand from players where id = v_turn_id;
  v_excess := coalesce(array_length(v_hand, 1), 0) - 7;
  if v_excess > 0 then
    v_discard_some := v_hand[array_length(v_hand, 1) - v_excess + 1:array_length(v_hand, 1)];
    update players set hand = v_hand[1:array_length(v_hand, 1) - v_excess]
      where id = v_turn_id;
    update game_state set discard_pile = discard_pile || v_discard_some where id = 1;
  end if;

  -- Forgive any active debts whose debtor is the AFK player.
  update game_state set payment_queue = (
    select coalesce(jsonb_agg(
      case when (e->>'debtor_id')::uuid = v_turn_id and e->>'status' in ('active','pending')
           then jsonb_set(e, '{status}', '"forgiven"') else e end
    ), '[]'::jsonb) from jsonb_array_elements(payment_queue) e
  ) where id = 1;
  perform _advance_payment_queue();

  perform _advance_turn();
  perform _append_log('host',
    'host force-ended ' || (select name from players where id = v_turn_id) || '''s turn');
  update game_state set version = version + 1, updated_at = now() where id = 1;
  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function public.host_force_end_turn(uuid, uuid) from public;
grant execute on function public.host_force_end_turn(uuid, uuid) to anon, authenticated;

-- ============================================================================
-- reset_to_lobby — keeps players + seats; clears game state. Goes to
-- character_select so everyone re-picks (or stays with same characters).
-- Per spec line 494: clears chosen_character + protected_color + petrified +
-- hand + bank + item_area + deck/discard/stack/queue/log/turn state. Phase →
-- character_select (or lobby if you prefer; character_select is the default).
-- Host only.
-- ============================================================================

create or replace function public.reset_to_lobby(
  p_actor_id uuid, p_actor_token uuid
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare v_host_id uuid;
begin
  perform 1 from game_state where id = 1 for update;
  perform _validate_token(p_actor_id, p_actor_token);
  select host_player_id into v_host_id from game_state where id = 1;
  if p_actor_id != v_host_id then raise exception 'not_host'; end if;

  update players set
    chosen_character = null,
    protected_color = null,
    petrified = false,
    hand = '{}', bank = '{}',
    item_area = '[]'::jsonb;

  update game_state set
    phase = 'character_select',
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
    log = jsonb_build_array(jsonb_build_object('at', now()::text, 'kind', 'reset', 'text', 'host started new game')),
    started_at = null,
    version = version + 1,
    updated_at = now()
  where id = 1;

  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function public.reset_to_lobby(uuid, uuid) from public;
grant execute on function public.reset_to_lobby(uuid, uuid) to anon, authenticated;

-- ============================================================================
-- host_kick_mid_game — remove a player whose hand+bank+items go to discard.
-- If < 2 players remain, auto-trigger Full Reset.
-- ============================================================================

create or replace function public.host_kick_mid_game(
  p_actor_id uuid, p_actor_token uuid, p_target_id uuid
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_host_id uuid;
  v_phase text;
  v_target_name text;
  v_target_hand uuid[];
  v_target_bank uuid[];
  v_item_cards uuid[];
  v_remaining int;
begin
  perform 1 from game_state where id = 1 for update;
  perform _validate_token(p_actor_id, p_actor_token);
  select host_player_id, phase into v_host_id, v_phase from game_state where id = 1;
  if p_actor_id != v_host_id then raise exception 'not_host'; end if;
  if p_target_id = v_host_id then raise exception 'cannot_kick_self'; end if;

  select name, hand, bank into v_target_name, v_target_hand, v_target_bank
    from players where id = p_target_id;
  if v_target_name is null then raise exception 'target_not_found'; end if;

  -- Collect all item card ids from target.
  select coalesce(array_agg((cc->>'card_id')::uuid), '{}'::uuid[])
    into v_item_cards
    from players p, jsonb_array_elements(p.item_area) col,
         jsonb_array_elements(col->'cards') cc
    where p.id = p_target_id;

  update game_state
    set discard_pile = discard_pile || coalesce(v_target_hand, '{}'::uuid[])
                                    || coalesce(v_target_bank, '{}'::uuid[])
                                    || v_item_cards
    where id = 1;

  delete from players where id = p_target_id;

  -- Compact seat indexes.
  with ordered as (
    select id, row_number() over (order by seat_index) - 1 as new_seat from players
  )
  update players p set seat_index = o.new_seat::int
    from ordered o where p.id = o.id;

  perform _append_log('kick', v_target_name || ' was kicked mid-game');

  -- If < 2 players, auto-full-reset.
  select count(*) into v_remaining from players;
  if v_remaining < 2 then
    delete from players where true;
    update game_state set
      phase = 'lobby', host_player_id = null, turn_player_id = null,
      deck_order = '{}', discard_pile = '{}',
      pending_stack = '[]'::jsonb, payment_queue = '[]'::jsonb,
      version = 0, updated_at = now()
    where id = 1;
  else
    -- If we kicked the active turn player, advance.
    if (select turn_player_id from game_state where id = 1) is null
       or not exists(select 1 from players where id = (select turn_player_id from game_state where id = 1)) then
      perform _advance_turn();
    end if;
    update game_state set version = version + 1, updated_at = now() where id = 1;
  end if;
  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function public.host_kick_mid_game(uuid, uuid, uuid) from public;
grant execute on function public.host_kick_mid_game(uuid, uuid, uuid) to anon, authenticated;
