-- get_my_hand — token-gated hand fetch. The public view exposes hand_count
-- only. This RPC lets a player retrieve their own card ids (then they fetch
-- card metadata from the public `cards` table separately).

create or replace function public.get_my_hand(p_actor_id uuid, p_actor_token uuid)
returns uuid[]
language plpgsql security definer set search_path = public stable
as $$
declare
  v_hand uuid[];
begin
  perform _validate_token(p_actor_id, p_actor_token);
  select hand into v_hand from players where id = p_actor_id;
  return coalesce(v_hand, '{}');
end;
$$;
revoke all on function public.get_my_hand(uuid, uuid) from public;
grant execute on function public.get_my_hand(uuid, uuid) to anon, authenticated;
