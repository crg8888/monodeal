-- Slice 3: minimum playable game (points + items only, no spells, no wilds).
-- Engine helpers + RPCs: start_turn, play_to_bank, play_item, end_turn.
--
-- Character abilities (Hermione's 4 plays, Luna's draw 3, Cedric discard) land
-- in Slice 8 alongside Petrificus. For Slice 3 every player draws 2 and gets
-- 3 plays per turn.

-- ============================================================================
-- _draw_cards — appends up to N cards from deck_order to player's hand.
-- Reshuffles discard into deck (excluding pending_stack + payment_queue cards)
-- when deck runs out mid-draw. Returns the number actually drawn.
-- ============================================================================

create or replace function public._draw_cards(p_player_id uuid, p_n int)
returns int
language plpgsql security definer set search_path = public
as $$
declare
  v_deck uuid[];
  v_discard uuid[];
  v_to_take uuid[];
  v_drawn int := 0;
  v_pending_ids uuid[];
  v_remaining int;
  v_take int;
begin
  select deck_order, discard_pile into v_deck, v_discard from game_state where id = 1;
  v_remaining := p_n;

  while v_remaining > 0 loop
    if coalesce(array_length(v_deck, 1), 0) > 0 then
      v_take := least(v_remaining, array_length(v_deck, 1));
      v_to_take := v_deck[1:v_take];
      v_deck := v_deck[v_take+1:array_length(v_deck, 1)];
      update players set hand = hand || v_to_take where id = p_player_id;
      v_drawn := v_drawn + v_take;
      v_remaining := v_remaining - v_take;
    elsif coalesce(array_length(v_discard, 1), 0) > 0 then
      -- Reshuffle: take discard minus pending_stack/payment_queue card refs.
      -- (For Slice 3 those are always empty; future-proofing the helper.)
      select coalesce(array_agg(distinct (frame->>'card_id')::uuid), '{}'::uuid[])
        into v_pending_ids
        from game_state, jsonb_array_elements(pending_stack) frame
        where id = 1 and frame ? 'card_id';
      v_deck := array(
        select unnest(v_discard) c
        where not (c = any(v_pending_ids))
        order by random()
      );
      v_discard := '{}';
      if coalesce(array_length(v_deck, 1), 0) = 0 then
        exit;
      end if;
    else
      exit;
    end if;
  end loop;

  update game_state set deck_order = v_deck, discard_pile = v_discard where id = 1;
  return v_drawn;
end;
$$;
revoke all on function public._draw_cards(uuid, int) from public;

-- ============================================================================
-- _count_complete_columns — number of distinct-color complete sets a player has.
-- A column is complete when count >= set_size AND it has at least one card
-- whose category is NOT 'wild_item_any_color' (per spec line 460-461).
-- ============================================================================

create or replace function public._count_complete_columns(p_player_id uuid)
returns int
language plpgsql security definer set search_path = public
as $$
declare
  v_count int;
begin
  with cols as (
    select col->>'color' as color,
           col->'cards' as cards
    from players, jsonb_array_elements(item_area) col
    where id = p_player_id
  ),
  expanded as (
    select c.color,
           jsonb_array_length(c.cards) as col_size,
           exists(
             select 1 from jsonb_array_elements(c.cards) cc
             join cards crd on crd.id = (cc->>'card_id')::uuid
             where crd.category != 'wild_item_any_color'
           ) as has_non_any_color,
           (select set_size from item_sets where color = c.color) as set_size
    from cols c
  ),
  completes as (
    select distinct color from expanded
    where col_size >= set_size and has_non_any_color
  )
  select count(*) into v_count from completes;
  return v_count;
end;
$$;
revoke all on function public._count_complete_columns(uuid) from public;

-- ============================================================================
-- _check_win — set winner_player_id + finished phase if player has >= 3
-- distinct-color complete sets AND no pending_stack / payment_queue activity.
-- ============================================================================

create or replace function public._check_win(p_player_id uuid)
returns bool
language plpgsql security definer set search_path = public
as $$
declare
  v_complete int;
  v_pending int;
  v_queue int;
begin
  v_complete := _count_complete_columns(p_player_id);
  select jsonb_array_length(pending_stack), jsonb_array_length(payment_queue)
    into v_pending, v_queue from game_state where id = 1;
  if v_complete >= 3 and coalesce(v_pending, 0) = 0 and coalesce(v_queue, 0) = 0 then
    update game_state
      set phase = 'finished',
          winner_player_id = p_player_id,
          updated_at = now()
      where id = 1;
    perform _append_log('win',
      (select name from players where id = p_player_id) || ' wins with 3 complete sets!');
    return true;
  end if;
  return false;
end;
$$;
revoke all on function public._check_win(uuid) from public;

-- ============================================================================
-- _advance_turn — leftward to next connected player; resets per-turn fields.
-- Plays Hermione's +1 will go in Slice 8.
-- ============================================================================

create or replace function public._advance_turn()
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_current_seat int;
  v_next_id uuid;
begin
  select p.seat_index into v_current_seat
    from game_state g join players p on p.id = g.turn_player_id
    where g.id = 1;
  if v_current_seat is null then
    -- Game just started; pick the first connected seat.
    select id into v_next_id from players
      where is_connected order by seat_index limit 1;
  else
    -- Next connected player by seat order, wrapping.
    select id into v_next_id from (
      select id, seat_index from players where is_connected
      order by case when seat_index > v_current_seat then 0 else 1 end, seat_index
    ) sub limit 1;
  end if;

  if v_next_id is null then return; end if;
  update game_state set
    turn_player_id = v_next_id,
    turn_number = turn_number + 1,
    plays_this_turn = 0,
    plays_allowed_this_turn = 3,
    has_drawn_this_turn = false,
    updated_at = now()
  where id = 1;
end;
$$;
revoke all on function public._advance_turn() from public;

-- ============================================================================
-- start_turn — active player draws (5 if hand empty, else 2).
-- ============================================================================

create or replace function public.start_turn(p_actor_id uuid, p_actor_token uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_phase text;
  v_turn_id uuid;
  v_drawn bool;
  v_hand_count int;
  v_n int;
  v_actually_drawn int;
begin
  perform 1 from game_state where id = 1 for update;
  perform _validate_token(p_actor_id, p_actor_token);
  select phase, turn_player_id, has_drawn_this_turn
    into v_phase, v_turn_id, v_drawn from game_state where id = 1;
  if v_phase != 'in_game' then raise exception 'wrong_phase' using detail = v_phase; end if;
  if v_turn_id != p_actor_id then raise exception 'not_your_turn'; end if;
  if v_drawn then raise exception 'already_drawn'; end if;

  select coalesce(array_length(hand, 1), 0) into v_hand_count
    from players where id = p_actor_id;
  v_n := case when v_hand_count = 0 then 5 else 2 end;
  v_actually_drawn := _draw_cards(p_actor_id, v_n);

  update game_state set has_drawn_this_turn = true,
                        version = version + 1, updated_at = now() where id = 1;
  perform _append_log('draw',
    (select name from players where id = p_actor_id) || ' drew ' || v_actually_drawn || ' cards');
  return jsonb_build_object('ok', true, 'drawn', v_actually_drawn);
end;
$$;
revoke all on function public.start_turn(uuid, uuid) from public;
grant execute on function public.start_turn(uuid, uuid) to anon, authenticated;

-- ============================================================================
-- play_to_bank — point or spell card moves from hand to bank. plays += 1.
-- Items / wilds rejected (they go in item_area only).
-- ============================================================================

create or replace function public.play_to_bank(
  p_actor_id uuid, p_actor_token uuid, p_card_id uuid
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_phase text;
  v_turn_id uuid;
  v_drawn bool;
  v_plays int;
  v_max_plays int;
  v_category text;
  v_in_hand bool;
begin
  perform 1 from game_state where id = 1 for update;
  perform _validate_token(p_actor_id, p_actor_token);
  select phase, turn_player_id, has_drawn_this_turn,
         plays_this_turn, plays_allowed_this_turn
    into v_phase, v_turn_id, v_drawn, v_plays, v_max_plays from game_state where id = 1;
  if v_phase != 'in_game' then raise exception 'wrong_phase' using detail = v_phase; end if;
  if v_turn_id != p_actor_id then raise exception 'not_your_turn'; end if;
  if not v_drawn then raise exception 'must_draw_first'; end if;
  if v_plays >= v_max_plays then raise exception 'no_plays_left'; end if;

  select category into v_category from cards where id = p_card_id;
  if v_category is null then raise exception 'unknown_card'; end if;
  if v_category in ('item','wild_item_two_color','wild_item_any_color') then
    raise exception 'items_cannot_bank';
  end if;
  if v_category = 'character' then raise exception 'characters_cannot_bank'; end if;

  select p_card_id = any(hand) into v_in_hand from players where id = p_actor_id;
  if not v_in_hand then raise exception 'card_not_in_hand'; end if;

  update players set
    hand = array_remove(hand, p_card_id),
    bank = bank || p_card_id
  where id = p_actor_id;

  update game_state set plays_this_turn = plays_this_turn + 1,
                        version = version + 1, updated_at = now() where id = 1;
  perform _append_log('bank',
    (select name from players where id = p_actor_id) || ' banked ' ||
    (select title from cards where id = p_card_id));
  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function public.play_to_bank(uuid, uuid, uuid) from public;
grant execute on function public.play_to_bank(uuid, uuid, uuid) to anon, authenticated;

-- ============================================================================
-- play_item — non-wild item to a column (existing or new).
-- Color must be in card.colors. plays += 1. Triggers _check_win after.
-- ============================================================================

create or replace function public.play_item(
  p_actor_id uuid, p_actor_token uuid, p_card_id uuid,
  p_color text, p_target_column_id uuid default null
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_phase text;
  v_turn_id uuid;
  v_drawn bool;
  v_plays int;
  v_max_plays int;
  v_category text;
  v_card_colors text[];
  v_in_hand bool;
  v_set_size int;
  v_item_area jsonb;
  v_new_area jsonb;
  v_new_card jsonb;
  v_target_idx int := -1;
  v_target_col jsonb;
  v_won bool;
begin
  perform 1 from game_state where id = 1 for update;
  perform _validate_token(p_actor_id, p_actor_token);
  select phase, turn_player_id, has_drawn_this_turn,
         plays_this_turn, plays_allowed_this_turn
    into v_phase, v_turn_id, v_drawn, v_plays, v_max_plays from game_state where id = 1;
  if v_phase != 'in_game' then raise exception 'wrong_phase' using detail = v_phase; end if;
  if v_turn_id != p_actor_id then raise exception 'not_your_turn'; end if;
  if not v_drawn then raise exception 'must_draw_first'; end if;
  if v_plays >= v_max_plays then raise exception 'no_plays_left'; end if;

  select category, colors into v_category, v_card_colors from cards where id = p_card_id;
  if v_category is null then raise exception 'unknown_card'; end if;
  if v_category not in ('item','wild_item_two_color','wild_item_any_color') then
    raise exception 'not_an_item';
  end if;
  -- Slice 3: only plain items (wilds covered in Slice 4).
  if v_category != 'item' then raise exception 'wilds_in_slice_4'; end if;
  if not (p_color = any(v_card_colors)) then
    raise exception 'illegal_color' using detail = p_color;
  end if;
  select p_card_id = any(hand) into v_in_hand from players where id = p_actor_id;
  if not v_in_hand then raise exception 'card_not_in_hand'; end if;

  select set_size into v_set_size from item_sets where color = p_color;
  if v_set_size is null then raise exception 'unknown_color' using detail = p_color; end if;

  select item_area into v_item_area from players where id = p_actor_id;
  v_new_card := jsonb_build_object('card_id', p_card_id, 'assigned_color', p_color);

  -- Find target column (if specified) or first non-complete column of color.
  if p_target_column_id is not null then
    for v_target_idx in 0 .. coalesce(jsonb_array_length(v_item_area), 0) - 1 loop
      v_target_col := v_item_area->v_target_idx;
      exit when (v_target_col->>'column_id')::uuid = p_target_column_id;
      v_target_idx := -1;
    end loop;
    if v_target_idx < 0 then raise exception 'unknown_column'; end if;
    if (v_target_col->>'color') != p_color then raise exception 'wrong_column_color'; end if;
    if jsonb_array_length(v_target_col->'cards') >= v_set_size then
      raise exception 'column_complete' using detail = (v_target_col->>'color');
    end if;
  else
    for v_target_idx in 0 .. coalesce(jsonb_array_length(v_item_area), 0) - 1 loop
      v_target_col := v_item_area->v_target_idx;
      if (v_target_col->>'color') = p_color
         and jsonb_array_length(v_target_col->'cards') < v_set_size then
        exit;
      end if;
      v_target_idx := -1;
    end loop;
  end if;

  if v_target_idx < 0 then
    -- New column.
    v_new_area := coalesce(v_item_area, '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
      'column_id', gen_random_uuid()::text,
      'color', p_color,
      'cards', jsonb_build_array(v_new_card)
    ));
  else
    -- Append to existing column.
    v_new_area := jsonb_set(
      v_item_area,
      array[v_target_idx::text, 'cards'],
      (v_item_area->v_target_idx->'cards') || v_new_card
    );
  end if;

  update players set
    hand = array_remove(hand, p_card_id),
    item_area = v_new_area
  where id = p_actor_id;

  update game_state set plays_this_turn = plays_this_turn + 1,
                        version = version + 1, updated_at = now() where id = 1;
  perform _append_log('item',
    (select name from players where id = p_actor_id) || ' played ' ||
    (select title from cards where id = p_card_id) || ' → ' || p_color);

  v_won := _check_win(p_actor_id);
  return jsonb_build_object('ok', true, 'won', v_won);
end;
$$;
revoke all on function public.play_item(uuid, uuid, uuid, text, uuid) from public;
grant execute on function public.play_item(uuid, uuid, uuid, text, uuid) to anon, authenticated;

-- ============================================================================
-- end_turn — advances turn. If hand > 7, requires p_discard_card_ids exactly
-- equal to (hand_count - 7). Server moves them to discard pile.
-- ============================================================================

create or replace function public.end_turn(
  p_actor_id uuid, p_actor_token uuid,
  p_discard_card_ids uuid[] default '{}'
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_phase text;
  v_turn_id uuid;
  v_hand uuid[];
  v_excess int;
  v_id uuid;
begin
  perform 1 from game_state where id = 1 for update;
  perform _validate_token(p_actor_id, p_actor_token);
  select phase, turn_player_id into v_phase, v_turn_id from game_state where id = 1;
  if v_phase != 'in_game' then raise exception 'wrong_phase' using detail = v_phase; end if;
  if v_turn_id != p_actor_id then raise exception 'not_your_turn'; end if;

  select hand into v_hand from players where id = p_actor_id;
  v_excess := coalesce(array_length(v_hand, 1), 0) - 7;
  if v_excess > 0 then
    if coalesce(array_length(p_discard_card_ids, 1), 0) != v_excess then
      return jsonb_build_object('status', 'must_discard', 'excess', v_excess);
    end if;
    foreach v_id in array p_discard_card_ids loop
      if not (v_id = any(v_hand)) then
        raise exception 'discard_not_in_hand' using detail = v_id::text;
      end if;
    end loop;
    update players set hand = array(select unnest(hand) except select unnest(p_discard_card_ids))
      where id = p_actor_id;
    update game_state set discard_pile = discard_pile || p_discard_card_ids
      where id = 1;
  end if;

  perform _advance_turn();
  perform _append_log('turn', 'turn ended');
  update game_state set version = version + 1, updated_at = now() where id = 1;
  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function public.end_turn(uuid, uuid, uuid[]) from public;
grant execute on function public.end_turn(uuid, uuid, uuid[]) to anon, authenticated;
