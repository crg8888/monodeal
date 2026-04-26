-- pay_debt's loop-based search for the active queue entry was raising
-- 'no_active_debt' even when one existed. Rewriting with a SQL ORDINALITY
-- query instead of a plpgsql FOR loop. Same external semantics; correct.

create or replace function public.pay_debt(
  p_actor_id uuid, p_actor_token uuid, p_card_ids uuid[]
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_queue jsonb;
  v_active_idx int;
  v_active jsonb;
  v_amount int;
  v_recipient uuid;
  v_total_paid int := 0;
  v_avail int;
  v_id uuid;
  v_cat text;
  v_cash int;
  v_assigned text;
  v_drained bool;
  v_recipients_to_check uuid[];
begin
  perform 1 from game_state where id = 1 for update;
  perform _validate_token(p_actor_id, p_actor_token);
  select payment_queue into v_queue from game_state where id = 1;

  select (ord - 1)::int, e
    into v_active_idx, v_active
    from jsonb_array_elements(v_queue) with ordinality as t(e, ord)
    where (e->>'debtor_id')::uuid = p_actor_id and (e->>'status') = 'active'
    limit 1;
  if v_active_idx is null then raise exception 'no_active_debt'; end if;

  v_amount := (v_active->>'amount')::int;
  v_recipient := (v_active->>'recipient_id')::uuid;
  v_avail := _player_available_cash(p_actor_id);

  foreach v_id in array p_card_ids loop
    if v_id = any((select bank from players where id = p_actor_id)) then
      select coalesce(cash_value, 0) into v_cash from cards where id = v_id;
      v_total_paid := v_total_paid + v_cash;
    elsif _column_idx_of(p_actor_id, v_id) >= 0 then
      select category, coalesce(cash_value, 0) into v_cat, v_cash from cards where id = v_id;
      if v_cat = 'wild_item_any_color' then raise exception 'cannot_pay_with_any_wild'; end if;
      v_total_paid := v_total_paid + v_cash;
    else
      raise exception 'card_not_payable' using detail = v_id::text;
    end if;
  end loop;

  if v_total_paid < v_amount and v_total_paid < v_avail then
    raise exception 'must_pay_all_available' using detail = format('paid=%s avail=%s amount=%s',
      v_total_paid, v_avail, v_amount);
  end if;

  foreach v_id in array p_card_ids loop
    if v_id = any((select bank from players where id = p_actor_id)) then
      update players set bank = array_remove(bank, v_id) where id = p_actor_id;
      update players set bank = bank || v_id where id = v_recipient;
    else
      select cc->>'assigned_color' into v_assigned
        from players p, jsonb_array_elements(p.item_area) col,
             jsonb_array_elements(col->'cards') cc
        where p.id = p_actor_id and (cc->>'card_id')::uuid = v_id;
      perform _take_item_from_column(p_actor_id, v_id);
      perform _add_item_to_player(v_recipient, v_id, coalesce(v_assigned, 'brown'));
    end if;
  end loop;

  v_queue := jsonb_set(v_queue, array[v_active_idx::text, 'status'],
                      to_jsonb(case when v_total_paid >= v_amount then 'completed' else 'completed_partial' end));
  update game_state set payment_queue = v_queue where id = 1;

  perform _append_log('payment',
    (select name from players where id = p_actor_id) || ' paid ' || v_total_paid ||
    ' to ' || (select name from players where id = v_recipient) ||
    case when v_total_paid < v_amount then ' (partial — ' || v_amount - v_total_paid || ' forgiven)' else '' end);

  v_drained := _advance_payment_queue();

  if v_drained then
    select array_agg(distinct (e->>'recipient_id')::uuid)
      into v_recipients_to_check
      from jsonb_array_elements(v_queue) e;
    if v_recipients_to_check is not null then
      foreach v_id in array v_recipients_to_check loop
        perform _check_win(v_id);
      end loop;
    end if;
    update game_state set payment_queue = '[]'::jsonb where id = 1;
  end if;

  update game_state set version = version + 1, updated_at = now() where id = 1;
  return jsonb_build_object('ok', true, 'drained', v_drained);
end;
$$;
revoke all on function public.pay_debt(uuid, uuid, uuid[]) from public;
grant execute on function public.pay_debt(uuid, uuid, uuid[]) to anon, authenticated;
