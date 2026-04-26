-- Slice 2: character select + start game.
-- RPCs: start_character_select, choose_character, set_protected_color, start_game.
-- Helper: _shuffle_and_deal (also reused in Slice 3+ for full reshuffles).

-- ============================================================================
-- start_character_select — host moves phase from 'lobby' to 'character_select'.
-- ============================================================================

create or replace function public.start_character_select(
  p_actor_id uuid, p_actor_token uuid
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_host_id uuid;
  v_phase text;
  v_count int;
begin
  perform 1 from game_state where id = 1 for update;
  perform _validate_token(p_actor_id, p_actor_token);
  select host_player_id, phase into v_host_id, v_phase from game_state where id = 1;
  if p_actor_id != v_host_id then raise exception 'not_host'; end if;
  if v_phase != 'lobby' then raise exception 'wrong_phase' using detail = v_phase; end if;
  select count(*) into v_count from players;
  if v_count < 2 then raise exception 'need_two_players'; end if;
  if v_count > 5 then raise exception 'too_many_players'; end if;

  update game_state
    set phase = 'character_select',
        version = version + 1,
        updated_at = now()
    where id = 1;
  perform _append_log('phase', 'character select');
  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function public.start_character_select(uuid, uuid) from public;
grant execute on function public.start_character_select(uuid, uuid) to anon, authenticated;

-- ============================================================================
-- choose_character — player picks a character; rejected if already taken.
-- Picking harry leaves protected_color null until set_protected_color resolves.
-- ============================================================================

create or replace function public.choose_character(
  p_actor_id uuid, p_actor_token uuid, p_slug text
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_phase text;
  v_taken_by uuid;
  v_player_name text;
begin
  perform 1 from game_state where id = 1 for update;
  perform _validate_token(p_actor_id, p_actor_token);
  select phase into v_phase from game_state where id = 1;
  if v_phase != 'character_select' then
    raise exception 'wrong_phase' using detail = v_phase;
  end if;
  if p_slug not in ('harry','draco','hermione','luna','cedric') then
    raise exception 'invalid_character' using detail = p_slug;
  end if;
  select id into v_taken_by from players where chosen_character = p_slug and id != p_actor_id;
  if v_taken_by is not null then
    raise exception 'character_taken' using detail = p_slug;
  end if;

  update players set chosen_character = p_slug, protected_color = null
    where id = p_actor_id;
  select name into v_player_name from players where id = p_actor_id;
  perform _append_log('character', v_player_name || ' picked ' || initcap(p_slug));
  update game_state set version = version + 1, updated_at = now() where id = 1;
  return jsonb_build_object('ok', true, 'needs_color', p_slug = 'harry');
end;
$$;
revoke all on function public.choose_character(uuid, uuid, text) from public;
grant execute on function public.choose_character(uuid, uuid, text) to anon, authenticated;

-- ============================================================================
-- set_protected_color — Harry locks his protected color (one-time).
-- ============================================================================

create or replace function public.set_protected_color(
  p_actor_id uuid, p_actor_token uuid, p_color text
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_phase text;
  v_char text;
begin
  perform 1 from game_state where id = 1 for update;
  perform _validate_token(p_actor_id, p_actor_token);
  select phase into v_phase from game_state where id = 1;
  if v_phase != 'character_select' then
    raise exception 'wrong_phase' using detail = v_phase;
  end if;
  select chosen_character into v_char from players where id = p_actor_id;
  if v_char != 'harry' then raise exception 'not_harry'; end if;
  if p_color not in (
    'brown','light-blue','pink','orange','light-green','black','red','yellow','dark-blue','dark-green'
  ) then
    raise exception 'invalid_color' using detail = p_color;
  end if;

  update players set protected_color = p_color where id = p_actor_id;
  perform _append_log('character', 'Harry protects ' || p_color);
  update game_state set version = version + 1, updated_at = now() where id = 1;
  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function public.set_protected_color(uuid, uuid, text) from public;
grant execute on function public.set_protected_color(uuid, uuid, text) to anon, authenticated;

-- ============================================================================
-- _shuffle_and_deal — internal helper. Shuffles non-character cards, deals 5
-- to each player, leaves remainder as deck_order. Wipes hands first.
-- ============================================================================

create or replace function public._shuffle_and_deal()
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_deck uuid[];
  v_player record;
  v_hand uuid[];
begin
  select array_agg(id order by random()) into v_deck
    from cards where category != 'character';

  for v_player in select id from players order by seat_index loop
    v_hand := v_deck[1:5];
    update players set hand = v_hand where id = v_player.id;
    v_deck := v_deck[6:array_length(v_deck, 1)];
  end loop;

  update game_state set deck_order = v_deck where id = 1;
end;
$$;
revoke all on function public._shuffle_and_deal() from public;

-- ============================================================================
-- start_game — host transitions character_select → in_game.
-- All players must have chosen_character; Harry must have protected_color.
-- Deals deck, randomizes the first turn_player_id.
-- ============================================================================

create or replace function public.start_game(
  p_actor_id uuid, p_actor_token uuid
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_host_id uuid;
  v_phase text;
  v_total int;
  v_locked int;
  v_harry_no_color int;
  v_first_player uuid;
begin
  perform 1 from game_state where id = 1 for update;
  perform _validate_token(p_actor_id, p_actor_token);
  select host_player_id, phase into v_host_id, v_phase from game_state where id = 1;
  if p_actor_id != v_host_id then raise exception 'not_host'; end if;
  if v_phase != 'character_select' then raise exception 'wrong_phase' using detail = v_phase; end if;

  select count(*), count(*) filter (where chosen_character is not null)
    into v_total, v_locked from players;
  if v_locked < v_total then raise exception 'players_not_ready'; end if;
  if v_total < 2 then raise exception 'need_two_players'; end if;
  if v_total > 5 then raise exception 'too_many_players'; end if;

  select count(*) into v_harry_no_color
    from players where chosen_character = 'harry' and protected_color is null;
  if v_harry_no_color > 0 then raise exception 'harry_color_unset'; end if;

  perform _shuffle_and_deal();

  -- Random first player
  select id into v_first_player from players order by random() limit 1;

  update game_state set
    phase = 'in_game',
    turn_player_id = v_first_player,
    turn_number = 1,
    plays_allowed_this_turn = 3,
    plays_this_turn = 0,
    has_drawn_this_turn = false,
    started_at = now(),
    version = version + 1,
    updated_at = now()
  where id = 1;
  perform _append_log('phase', 'game starts — turn 1');
  return jsonb_build_object('ok', true, 'first_player', v_first_player);
end;
$$;
revoke all on function public.start_game(uuid, uuid) from public;
grant execute on function public.start_game(uuid, uuid) to anon, authenticated;
