-- Slice 8: Petrificus Totalus removal + character abilities.
--   - Hermione: 4 plays per turn instead of 3 (when not petrified).
--   - Luna: at start of turn, draws 3 (or 5 on empty hand).
--   - Cedric: may draw top of discard instead of deck.
--   - Petrificus removal: discard >= 10 pts from bank to break it (default
--     setting petrificus_removal_sources = ['bank']).

-- ============================================================================
-- _compute_plays_allowed
-- ============================================================================

create or replace function public._compute_plays_allowed(p_player_id uuid)
returns int
language plpgsql security definer set search_path = public stable
as $$
declare v_char text; v_petrified bool;
begin
  select chosen_character, petrified into v_char, v_petrified
    from players where id = p_player_id;
  return case when v_char = 'hermione' and not coalesce(v_petrified, false) then 4 else 3 end;
end;
$$;
revoke all on function public._compute_plays_allowed(uuid) from public;

-- ============================================================================
-- _compute_draw_count
-- ============================================================================

create or replace function public._compute_draw_count(p_player_id uuid, p_hand_empty bool)
returns int
language plpgsql security definer set search_path = public stable
as $$
declare v_char text; v_petrified bool;
begin
  select chosen_character, petrified into v_char, v_petrified
    from players where id = p_player_id;
  return case
    when p_hand_empty then 5
    when v_char = 'luna' and not coalesce(v_petrified, false) then 3
    else 2
  end;
end;
$$;
revoke all on function public._compute_draw_count(uuid, bool) from public;

-- ============================================================================
-- _advance_turn — now sets plays_allowed_this_turn based on next player's
-- character + petrified status.
-- ============================================================================

create or replace function public._advance_turn()
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_current_seat int;
  v_next_id uuid;
  v_plays int;
begin
  select p.seat_index into v_current_seat
    from game_state g join players p on p.id = g.turn_player_id
    where g.id = 1;
  if v_current_seat is null then
    select id into v_next_id from players
      where is_connected order by seat_index limit 1;
  else
    select id into v_next_id from (
      select id, seat_index from players where is_connected
      order by case when seat_index > v_current_seat then 0 else 1 end, seat_index
    ) sub limit 1;
  end if;

  if v_next_id is null then return; end if;
  v_plays := _compute_plays_allowed(v_next_id);
  update game_state set
    turn_player_id = v_next_id,
    turn_number = turn_number + 1,
    plays_this_turn = 0,
    plays_allowed_this_turn = v_plays,
    has_drawn_this_turn = false,
    updated_at = now()
  where id = 1;
end;
$$;
revoke all on function public._advance_turn() from public;

-- ============================================================================
-- start_turn — extended for Luna's draw 3 + Cedric's discard draw.
-- New optional param p_from_discard: when true and Cedric not petrified and
-- discard non-empty, draw 1 from discard top + (count-1) from deck.
-- ============================================================================

create or replace function public.start_turn(
  p_actor_id uuid, p_actor_token uuid,
  p_from_discard bool default false
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_phase text;
  v_turn_id uuid;
  v_drawn bool;
  v_hand_count int;
  v_n int;
  v_actually_drawn int;
  v_char text;
  v_petrified bool;
  v_discard uuid[];
  v_top_discard uuid;
begin
  perform 1 from game_state where id = 1 for update;
  perform _validate_token(p_actor_id, p_actor_token);
  select phase, turn_player_id, has_drawn_this_turn, discard_pile
    into v_phase, v_turn_id, v_drawn, v_discard from game_state where id = 1;
  if v_phase != 'in_game' then raise exception 'wrong_phase' using detail = v_phase; end if;
  if v_turn_id != p_actor_id then raise exception 'not_your_turn'; end if;
  if v_drawn then raise exception 'already_drawn'; end if;

  select chosen_character, petrified, coalesce(array_length(hand, 1), 0)
    into v_char, v_petrified, v_hand_count
    from players where id = p_actor_id;

  v_n := _compute_draw_count(p_actor_id, v_hand_count = 0);

  -- Cedric branch: top of discard for the FIRST card.
  if p_from_discard and v_char = 'cedric' and not coalesce(v_petrified, false)
     and coalesce(array_length(v_discard, 1), 0) > 0 then
    v_top_discard := v_discard[array_length(v_discard, 1)];
    update players set hand = hand || v_top_discard where id = p_actor_id;
    update game_state set discard_pile = v_discard[1:array_length(v_discard, 1) - 1]
      where id = 1;
    -- Then draw remaining (n-1) from deck.
    v_actually_drawn := 1 + _draw_cards(p_actor_id, v_n - 1);
  else
    v_actually_drawn := _draw_cards(p_actor_id, v_n);
  end if;

  -- Recompute plays_allowed in case character was petrified mid-cycle.
  update game_state set
    has_drawn_this_turn = true,
    plays_allowed_this_turn = _compute_plays_allowed(p_actor_id),
    version = version + 1, updated_at = now()
  where id = 1;
  perform _append_log('draw',
    (select name from players where id = p_actor_id) || ' drew ' || v_actually_drawn);
  return jsonb_build_object('ok', true, 'drawn', v_actually_drawn);
end;
$$;
revoke all on function public.start_turn(uuid, uuid, bool) from public;
grant execute on function public.start_turn(uuid, uuid, bool) to anon, authenticated;
-- Drop the old 2-arg signature so callers don't get a stale variant.
drop function if exists public.start_turn(uuid, uuid);

-- ============================================================================
-- remove_petrificus — caller is petrified; discards >= 10 cash from bank to
-- break it. Petrificus card(s) attached to caller go to discard. Free action
-- (no play consumed). Active-turn-player only.
-- ============================================================================

create or replace function public.remove_petrificus(
  p_actor_id uuid, p_actor_token uuid, p_card_ids uuid[]
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_phase text;
  v_turn_id uuid;
  v_petrified bool;
  v_total int := 0;
  v_id uuid;
  v_cash int;
  v_in_bank bool;
  v_petr_ids uuid[];
begin
  perform 1 from game_state where id = 1 for update;
  perform _validate_token(p_actor_id, p_actor_token);
  select phase, turn_player_id into v_phase, v_turn_id from game_state where id = 1;
  if v_phase != 'in_game' then raise exception 'wrong_phase' using detail = v_phase; end if;
  if v_turn_id != p_actor_id then raise exception 'not_your_turn'; end if;
  select petrified into v_petrified from players where id = p_actor_id;
  if not coalesce(v_petrified, false) then raise exception 'not_petrified'; end if;

  foreach v_id in array p_card_ids loop
    select v_id = any(bank) into v_in_bank from players where id = p_actor_id;
    if not v_in_bank then raise exception 'card_not_in_bank' using detail = v_id::text; end if;
    select coalesce(cash_value, 0) into v_cash from cards where id = v_id;
    v_total := v_total + v_cash;
  end loop;
  if v_total < 10 then raise exception 'need_ten_points' using detail = v_total::text; end if;

  -- Move discard cards out of bank.
  update players set bank = array(
    select unnest(bank) except select unnest(p_card_ids)
  ) where id = p_actor_id;
  update game_state set discard_pile = discard_pile || p_card_ids where id = 1;

  -- Find any petrificus cards still in bank (we stored them there in Slice 5).
  select array_agg(b) into v_petr_ids
    from (
      select unnest(bank) as b from players where id = p_actor_id
    ) sub
    join cards c on c.id = sub.b
    where c.spell_effect = 'petrificus_totalus';
  if v_petr_ids is not null then
    update players set bank = array(
      select unnest(bank) except select unnest(v_petr_ids)
    ) where id = p_actor_id;
    update game_state set discard_pile = discard_pile || v_petr_ids where id = 1;
  end if;

  update players set petrified = false where id = p_actor_id;
  -- Recompute plays_allowed (Hermione unpetrify mid-turn → 4).
  update game_state set
    plays_allowed_this_turn = _compute_plays_allowed(p_actor_id),
    version = version + 1, updated_at = now()
  where id = 1;
  perform _append_log('petrificus',
    (select name from players where id = p_actor_id) || ' broke Petrificus (paid ' || v_total || ')');
  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function public.remove_petrificus(uuid, uuid, uuid[]) from public;
grant execute on function public.remove_petrificus(uuid, uuid, uuid[]) to anon, authenticated;
