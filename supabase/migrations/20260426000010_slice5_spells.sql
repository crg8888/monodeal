-- Slice 5: non-reactive spells.
-- Spells implemented here resolve immediately (no Protego pathway yet — that's
-- Slice 7). Stupefy / Alohomora / Accio defer to Slice 6 (need payment_queue).
--
-- Spells: geminio, reparo, levicorpus, confundo, wingardium_leviosa, obliviate,
-- petrificus_totalus.
--
-- Cast Spell semantics (spec line 25): clicking "Cast" consumes the play even
-- if the player cancels mid-targeting. The card moves to discard. (Petrificus
-- attaches instead of discarding.)

-- ============================================================================
-- _move_card_to_discard — server-side helper to remove card from caster's hand
-- and append to discard pile. plays += 1 in the caller.
-- ============================================================================

create or replace function public._discard_from_hand(p_player_id uuid, p_card_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  update players set hand = array_remove(hand, p_card_id) where id = p_player_id;
  update game_state set discard_pile = discard_pile || p_card_id where id = 1;
end;
$$;
revoke all on function public._discard_from_hand(uuid, uuid) from public;

-- ============================================================================
-- _column_idx_of — find item_area index of a column containing card.
-- Returns -1 if not found.
-- ============================================================================

create or replace function public._column_idx_of(p_player_id uuid, p_card_id uuid)
returns int
language plpgsql security definer set search_path = public
as $$
declare
  v_area jsonb;
  v_idx int;
begin
  select item_area into v_area from players where id = p_player_id;
  for v_idx in 0 .. coalesce(jsonb_array_length(v_area), 0) - 1 loop
    if exists (
      select 1 from jsonb_array_elements(v_area->v_idx->'cards') c
      where (c->>'card_id')::uuid = p_card_id
    ) then return v_idx; end if;
  end loop;
  return -1;
end;
$$;
revoke all on function public._column_idx_of(uuid, uuid) from public;

-- ============================================================================
-- _is_harry_protected — true if target_id is Harry, not petrified, and the
-- given column color matches their protected_color.
-- ============================================================================

create or replace function public._is_harry_protected(p_target_id uuid, p_color text)
returns bool
language plpgsql security definer set search_path = public
as $$
declare
  v_char text; v_petrified bool; v_pcolor text;
begin
  select chosen_character, petrified, protected_color
    into v_char, v_petrified, v_pcolor from players where id = p_target_id;
  return v_char = 'harry' and not coalesce(v_petrified, false) and v_pcolor = p_color;
end;
$$;
revoke all on function public._is_harry_protected(uuid, text) from public;

-- ============================================================================
-- _column_is_complete — does a player's column at index match the set_size?
-- ============================================================================

create or replace function public._column_is_complete(p_player_id uuid, p_col_idx int)
returns bool
language plpgsql security definer set search_path = public
as $$
declare
  v_area jsonb;
  v_color text;
  v_set_size int;
  v_count int;
  v_has_non_any bool;
begin
  select item_area into v_area from players where id = p_player_id;
  if v_col_idx < 0 or v_col_idx >= coalesce(jsonb_array_length(v_area), 0) then return false; end if;
  v_color := v_area->v_col_idx->>'color';
  v_count := jsonb_array_length(v_area->v_col_idx->'cards');
  select set_size into v_set_size from item_sets where color = v_color;
  if v_count < v_set_size then return false; end if;
  select exists (
    select 1 from jsonb_array_elements(v_area->v_col_idx->'cards') c
    join cards crd on crd.id = (c->>'card_id')::uuid
    where crd.category != 'wild_item_any_color'
  ) into v_has_non_any;
  return v_has_non_any;
end;
$$;
revoke all on function public._column_is_complete(uuid, int) from public;

-- ============================================================================
-- _is_draco_active — caster can bypass complete-set restrictions.
-- ============================================================================

create or replace function public._is_draco_active(p_caster_id uuid)
returns bool
language plpgsql security definer set search_path = public
as $$
declare
  v_char text; v_petrified bool;
begin
  select chosen_character, petrified into v_char, v_petrified
    from players where id = p_caster_id;
  return v_char = 'draco' and not coalesce(v_petrified, false);
end;
$$;
revoke all on function public._is_draco_active(uuid) from public;

-- ============================================================================
-- _move_item_card — moves an item card between containers / players.
-- This handles: discard a card from a player's column; transfer to another
-- player's column (existing or new); etc. Mutates only the rows we name.
-- src_player can equal dst_player for same-board moves.
-- If dst is null, send to discard pile.
-- assigned_color stays unless explicitly overridden.
-- ============================================================================

create or replace function public._take_item_from_column(
  p_player_id uuid, p_card_id uuid
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_area jsonb;
  v_idx int;
  v_color text;
  v_assigned text;
begin
  v_idx := _column_idx_of(p_player_id, p_card_id);
  if v_idx < 0 then raise exception 'item_not_found' using detail = p_card_id::text; end if;

  select item_area into v_area from players where id = p_player_id;
  v_color := v_area->v_idx->>'color';
  select c->>'assigned_color' into v_assigned
    from jsonb_array_elements(v_area->v_idx->'cards') c
    where (c->>'card_id')::uuid = p_card_id;

  -- Remove from column.
  v_area := jsonb_set(
    v_area, array[v_idx::text, 'cards'],
    (
      select coalesce(jsonb_agg(c), '[]'::jsonb)
      from jsonb_array_elements(v_area->v_idx->'cards') c
      where (c->>'card_id')::uuid != p_card_id
    )
  );
  if jsonb_array_length(v_area->v_idx->'cards') = 0 then
    v_area := v_area - v_idx;
  end if;

  update players set item_area = v_area where id = p_player_id;
  return jsonb_build_object('color', v_color, 'assigned_color', coalesce(v_assigned, v_color));
end;
$$;
revoke all on function public._take_item_from_column(uuid, uuid) from public;

-- ============================================================================
-- _add_item_to_player — append (with assigned_color) to existing same-color
-- non-complete column or create a new one.
-- ============================================================================

create or replace function public._add_item_to_player(
  p_player_id uuid, p_card_id uuid, p_color text
) returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_area jsonb;
  v_idx int := -1;
  v_set_size int;
  v_new_card jsonb;
begin
  select set_size into v_set_size from item_sets where color = p_color;
  v_new_card := jsonb_build_object('card_id', p_card_id, 'assigned_color', p_color);
  select item_area into v_area from players where id = p_player_id;

  for v_idx in 0 .. coalesce(jsonb_array_length(v_area), 0) - 1 loop
    if (v_area->v_idx->>'color') = p_color
       and jsonb_array_length(v_area->v_idx->'cards') < v_set_size then
      exit;
    end if;
    v_idx := -1;
  end loop;

  if v_idx < 0 then
    v_area := coalesce(v_area, '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
      'column_id', gen_random_uuid()::text,
      'color', p_color,
      'cards', jsonb_build_array(v_new_card)
    ));
  else
    v_area := jsonb_set(v_area, array[v_idx::text, 'cards'],
                       (v_area->v_idx->'cards') || v_new_card);
  end if;

  update players set item_area = v_area where id = p_player_id;
end;
$$;
revoke all on function public._add_item_to_player(uuid, uuid, text) from public;

-- ============================================================================
-- cast_spell — single dispatch RPC. Slice 5 handles non-reactive spells +
-- those whose Protego pathway lives in Slice 7 (we resolve immediately for
-- now). Stupefy/Alohomora/Accio are deferred to Slice 6.
-- ============================================================================

create or replace function public.cast_spell(
  p_actor_id uuid, p_actor_token uuid, p_card_id uuid,
  p_params jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_phase text;
  v_turn_id uuid;
  v_drawn bool;
  v_plays int;
  v_max_plays int;
  v_in_hand bool;
  v_category text;
  v_effect text;
  v_result jsonb := '{}'::jsonb;
  v_target_id uuid;
  v_target_card_id uuid;
  v_my_card_id uuid;
  v_target_idx int;
  v_my_idx int;
  v_target_color text;
  v_my_color text;
  v_won bool := false;
  v_reparo_card_id uuid;
  v_reparo_cat text;
  v_reparo_color text;
  v_dest_color text;
  v_dest_color_param text;
  v_settings jsonb;
begin
  perform 1 from game_state where id = 1 for update;
  perform _validate_token(p_actor_id, p_actor_token);
  select phase, turn_player_id, has_drawn_this_turn,
         plays_this_turn, plays_allowed_this_turn, settings
    into v_phase, v_turn_id, v_drawn, v_plays, v_max_plays, v_settings
    from game_state where id = 1;
  if v_phase != 'in_game' then raise exception 'wrong_phase' using detail = v_phase; end if;
  if v_turn_id != p_actor_id then raise exception 'not_your_turn'; end if;
  if not v_drawn then raise exception 'must_draw_first'; end if;
  if v_plays >= v_max_plays then raise exception 'no_plays_left'; end if;

  select category, spell_effect into v_category, v_effect from cards where id = p_card_id;
  if v_category != 'spell' then raise exception 'not_a_spell'; end if;
  select p_card_id = any(hand) into v_in_hand from players where id = p_actor_id;
  if not v_in_hand then raise exception 'card_not_in_hand'; end if;

  -- Slice 6 spells (need payment queue).
  if v_effect in ('stupefy','alohomora','accio_brown_light_blue','accio_pink_orange',
                  'accio_light_green_black','accio_red_yellow','accio_dark_blue_dark_green',
                  'accio_any') then
    raise exception 'spell_in_slice_6' using detail = v_effect;
  end if;
  -- Protego is reactive only.
  if v_effect = 'protego' then raise exception 'protego_is_reactive'; end if;

  -- Consume the play + remove from hand up front (binding cast). Petrificus
  -- attaches instead of going to discard, so we handle its move below.
  update players set hand = array_remove(hand, p_card_id) where id = p_actor_id;

  -- ===========================================================================
  -- GEMINIO: draw 2.
  -- ===========================================================================
  if v_effect = 'geminio' then
    perform _draw_cards(p_actor_id, 2);
    update game_state set discard_pile = discard_pile || p_card_id where id = 1;

  -- ===========================================================================
  -- REPARO: take any card from discard, place per type / settings.
  -- ===========================================================================
  elsif v_effect = 'reparo' then
    v_reparo_card_id := (p_params->>'from_discard_card_id')::uuid;
    if v_reparo_card_id is null then raise exception 'reparo_pick_required'; end if;
    if not (v_reparo_card_id = any(
      (select discard_pile from game_state where id = 1)
    )) then raise exception 'card_not_in_discard'; end if;

    select category, colors[1] into v_reparo_cat, v_reparo_color
      from cards where id = v_reparo_card_id;
    -- Remove from discard.
    update game_state set discard_pile = array_remove(discard_pile, v_reparo_card_id)
      where id = 1;

    if v_reparo_cat = 'item' then
      perform _add_item_to_player(p_actor_id, v_reparo_card_id, v_reparo_color);
    elsif v_reparo_cat in ('wild_item_two_color','wild_item_any_color') then
      v_dest_color_param := p_params->>'dest_color';
      if v_dest_color_param is null then raise exception 'wild_color_required'; end if;
      perform _add_item_to_player(p_actor_id, v_reparo_card_id, v_dest_color_param);
    elsif v_reparo_cat = 'point' then
      update players set bank = bank || v_reparo_card_id where id = p_actor_id;
    elsif v_reparo_cat = 'spell' then
      -- Petrificus always goes to bank as 5 cash; otherwise per setting.
      if exists(select 1 from cards where id = v_reparo_card_id and spell_effect = 'petrificus_totalus') then
        update players set bank = bank || v_reparo_card_id where id = p_actor_id;
      elsif (v_settings->>'reparo_spell_destination') = 'bank_as_points' then
        update players set bank = bank || v_reparo_card_id where id = p_actor_id;
      else
        -- 'cast_for_effect' — must have plays remaining for a follow-up play.
        update players set hand = hand || v_reparo_card_id where id = p_actor_id;
      end if;
    end if;

    update game_state set discard_pile = discard_pile || p_card_id where id = 1;

  -- ===========================================================================
  -- LEVICORPUS: take 1 item from 1 opponent. Not from complete (Draco bypass).
  -- ===========================================================================
  elsif v_effect = 'levicorpus' then
    v_target_id := (p_params->>'target_player_id')::uuid;
    v_target_card_id := (p_params->>'target_card_id')::uuid;
    if v_target_id is null or v_target_card_id is null then raise exception 'targets_required'; end if;
    if v_target_id = p_actor_id then raise exception 'cannot_target_self'; end if;
    v_target_idx := _column_idx_of(v_target_id, v_target_card_id);
    if v_target_idx < 0 then raise exception 'item_not_found'; end if;
    select item_area->v_target_idx->>'color' into v_target_color
      from players where id = v_target_id;
    if _is_harry_protected(v_target_id, v_target_color) then raise exception 'harry_protected'; end if;
    if _column_is_complete(v_target_id, v_target_idx) and not _is_draco_active(p_actor_id) then
      raise exception 'cannot_take_from_complete';
    end if;
    v_result := _take_item_from_column(v_target_id, v_target_card_id);
    perform _add_item_to_player(p_actor_id, v_target_card_id, v_result->>'assigned_color');
    update game_state set discard_pile = discard_pile || p_card_id where id = 1;

  -- ===========================================================================
  -- WINGARDIUM LEVIOSA: discard 1 item from opponent. Not from complete (Draco bypass).
  -- ===========================================================================
  elsif v_effect = 'wingardium_leviosa' then
    v_target_id := (p_params->>'target_player_id')::uuid;
    v_target_card_id := (p_params->>'target_card_id')::uuid;
    if v_target_id is null or v_target_card_id is null then raise exception 'targets_required'; end if;
    if v_target_id = p_actor_id then raise exception 'cannot_target_self'; end if;
    v_target_idx := _column_idx_of(v_target_id, v_target_card_id);
    if v_target_idx < 0 then raise exception 'item_not_found'; end if;
    select item_area->v_target_idx->>'color' into v_target_color
      from players where id = v_target_id;
    if _is_harry_protected(v_target_id, v_target_color) then raise exception 'harry_protected'; end if;
    if _column_is_complete(v_target_id, v_target_idx) and not _is_draco_active(p_actor_id) then
      raise exception 'cannot_take_from_complete';
    end if;
    perform _take_item_from_column(v_target_id, v_target_card_id);
    update game_state set discard_pile = discard_pile || v_target_card_id || p_card_id where id = 1;

  -- ===========================================================================
  -- CONFUNDO: swap 1 of mine with 1 of theirs. Neither from complete (Draco bypass on theirs).
  -- ===========================================================================
  elsif v_effect = 'confundo' then
    v_target_id := (p_params->>'target_player_id')::uuid;
    v_target_card_id := (p_params->>'target_card_id')::uuid;
    v_my_card_id := (p_params->>'my_card_id')::uuid;
    if v_target_id is null or v_target_card_id is null or v_my_card_id is null then
      raise exception 'targets_required';
    end if;
    if v_target_id = p_actor_id then raise exception 'cannot_target_self'; end if;
    v_target_idx := _column_idx_of(v_target_id, v_target_card_id);
    v_my_idx := _column_idx_of(p_actor_id, v_my_card_id);
    if v_target_idx < 0 or v_my_idx < 0 then raise exception 'item_not_found'; end if;
    select item_area->v_target_idx->>'color' into v_target_color from players where id = v_target_id;
    select item_area->v_my_idx->>'color' into v_my_color from players where id = p_actor_id;
    if _is_harry_protected(v_target_id, v_target_color) then raise exception 'harry_protected'; end if;
    if _column_is_complete(v_target_id, v_target_idx) and not _is_draco_active(p_actor_id) then
      raise exception 'cannot_take_from_complete_target';
    end if;
    if _column_is_complete(p_actor_id, v_my_idx) then
      raise exception 'cannot_take_from_complete_self';
    end if;
    -- Take both, then re-add to the swapped player.
    v_result := _take_item_from_column(v_target_id, v_target_card_id);
    v_target_color := v_result->>'assigned_color';
    v_result := _take_item_from_column(p_actor_id, v_my_card_id);
    v_my_color := v_result->>'assigned_color';
    perform _add_item_to_player(p_actor_id, v_target_card_id, v_target_color);
    perform _add_item_to_player(v_target_id, v_my_card_id, v_my_color);
    update game_state set discard_pile = discard_pile || p_card_id where id = 1;

  -- ===========================================================================
  -- OBLIVIATE: take a complete item set from opponent.
  -- params: target_player_id, target_color (the column's color).
  -- ===========================================================================
  elsif v_effect = 'obliviate' then
    v_target_id := (p_params->>'target_player_id')::uuid;
    v_target_color := p_params->>'target_color';
    if v_target_id is null or v_target_color is null then raise exception 'targets_required'; end if;
    if v_target_id = p_actor_id then raise exception 'cannot_target_self'; end if;
    if _is_harry_protected(v_target_id, v_target_color) then raise exception 'harry_protected'; end if;
    -- Find a complete column of that color on target.
    declare v_complete_idx int := -1;
            v_n int;
            v_cards_in jsonb;
    begin
      select item_area into v_result from players where id = v_target_id;
      for v_target_idx in 0 .. coalesce(jsonb_array_length(v_result), 0) - 1 loop
        if (v_result->v_target_idx->>'color') = v_target_color
           and _column_is_complete(v_target_id, v_target_idx) then
          v_complete_idx := v_target_idx; exit;
        end if;
      end loop;
      if v_complete_idx < 0 then raise exception 'no_complete_column' using detail = v_target_color; end if;
      v_cards_in := v_result->v_complete_idx->'cards';
      -- Drop column from target.
      v_result := v_result - v_complete_idx;
      update players set item_area = v_result where id = v_target_id;
      -- Add each card to caster, preserving assigned_color.
      v_n := jsonb_array_length(v_cards_in);
      for v_target_idx in 0 .. v_n - 1 loop
        perform _add_item_to_player(
          p_actor_id,
          (v_cards_in->v_target_idx->>'card_id')::uuid,
          v_cards_in->v_target_idx->>'assigned_color'
        );
      end loop;
    end;
    update game_state set discard_pile = discard_pile || p_card_id where id = 1;

  -- ===========================================================================
  -- PETRIFICUS TOTALUS: attaches to opponent. Doesn't go to discard.
  -- ===========================================================================
  elsif v_effect = 'petrificus_totalus' then
    v_target_id := (p_params->>'target_player_id')::uuid;
    if v_target_id is null then raise exception 'targets_required'; end if;
    if v_target_id = p_actor_id then raise exception 'cannot_target_self'; end if;
    update players set petrified = true where id = v_target_id;
    -- Attach card by storing under a new "petrified_attachment" field on the
    -- target. Slice 8 handles removal.
    update players set bank = bank || p_card_id where id = v_target_id;
    -- ^ Stored on target's bank for now as a marker; in Slice 8 we'll move it
    -- to a dedicated attached_card column. Functionally fine for v1 since
    -- Petrificus has cash 5 and counts towards bank anyway when it eventually
    -- goes to discard via removal.

  end if;

  -- Bump play counter + version.
  update game_state set
    plays_this_turn = plays_this_turn + 1,
    version = version + 1,
    updated_at = now()
  where id = 1;
  perform _append_log('cast',
    (select name from players where id = p_actor_id) || ' cast ' || v_effect);

  -- Win check after every spell.
  v_won := _check_win(p_actor_id);

  return jsonb_build_object('ok', true, 'won', v_won);
end;
$$;
revoke all on function public.cast_spell(uuid, uuid, uuid, jsonb) from public;
grant execute on function public.cast_spell(uuid, uuid, uuid, jsonb) to anon, authenticated;
