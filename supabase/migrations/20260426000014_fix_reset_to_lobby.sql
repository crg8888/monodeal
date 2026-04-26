-- Same Supabase safety guard ("UPDATE requires WHERE clause") affects the
-- bulk player update inside reset_to_lobby. Add a trivial WHERE.

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
    item_area = '[]'::jsonb
  where true;

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
