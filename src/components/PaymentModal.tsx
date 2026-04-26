import { useState } from 'react';
import { supabase } from '../lib/supabase';
import { getIdentity } from '../lib/identity';
import { broadcastStateChanged, useGameStore } from '../state/gameStore';
import { Card as CardView, colorHex } from './Card';
import { ITEM_SETS, colorHumanName } from '../lib/rules';
import type { Card as CardData, ItemColumn, PaymentQueueItem } from '../types/game';

export function PaymentModal(props: {
  debt: PaymentQueueItem;
  onClose?: () => void;
}) {
  const me = getIdentity()!;
  const players = useGameStore((s) => s.players);
  const cards = useGameStore((s) => s.cards);
  const refresh = useGameStore((s) => s.refresh);
  const fetchMyHand = useGameStore((s) => s.fetchMyHand);
  const myPlayer = players.find((p) => p.id === me.player_id)!;
  const recipient = players.find((p) => p.id === props.debt.recipient_id);

  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [working, setWorking] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const cardLookup = (id: string) => cards[id];

  const bankCards = myPlayer.bank
    .map((id) => cards[id])
    .filter((c): c is CardData => !!c);
  const itemCards: { card: CardData; col: ItemColumn }[] = [];
  for (const col of myPlayer.item_area) {
    for (const c of col.cards) {
      const card = cards[c.card_id];
      if (card && card.category !== 'wild_item_any_color') {
        itemCards.push({ card, col });
      }
    }
  }

  const totalSelected = Array.from(selected).reduce((sum, id) => {
    return sum + (cards[id]?.cash_value ?? 0);
  }, 0);

  const totalAvailable = bankCards.reduce((s, c) => s + (c.cash_value ?? 0), 0)
    + itemCards.reduce((s, { card }) => s + (card.cash_value ?? 0), 0);

  const debtAmount = props.debt.amount;
  const willPayInFull = totalSelected >= debtAmount;
  const mustPayAll = totalAvailable < debtAmount;
  const canSubmit = willPayInFull
    || (mustPayAll && totalSelected === totalAvailable && Array.from(selected).length === bankCards.length + itemCards.length);

  const toggle = (id: string) => {
    const next = new Set(selected);
    if (next.has(id)) next.delete(id); else next.add(id);
    setSelected(next);
  };

  const submit = async () => {
    setWorking(true);
    setError(null);
    const { error: err } = await supabase.rpc('pay_debt', {
      p_actor_id: me.player_id,
      p_actor_token: me.player_token,
      p_card_ids: Array.from(selected),
    });
    if (err) {
      setError(err.message);
      setWorking(false);
      return;
    }
    await broadcastStateChanged();
    await refresh();
    await fetchMyHand(me.player_id, me.player_token);
    setWorking(false);
    props.onClose?.();
  };

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center p-4 z-50">
      <div className="bg-white rounded-lg max-w-3xl w-full p-6 max-h-[95vh] overflow-auto">
        <div className="flex items-center justify-between mb-2">
          <div>
            <div className="text-xs text-stone-500">Pay debt</div>
            <h2 className="text-xl font-bold text-stone-900">
              You owe {recipient?.name ?? 'someone'} {debtAmount} cash
            </h2>
          </div>
        </div>
        <p className="text-sm text-stone-500 mb-3">
          Pick cards from your bank or items.
          {mustPayAll
            ? <> You don't have enough — you must pay everything ({totalAvailable}). The rest is forgiven.</>
            : <> Overpayment is lost (no change given).</>}
        </p>

        {error && (
          <div className="mb-3 p-2 bg-red-50 border border-red-200 text-red-900 text-sm rounded">
            {error}
          </div>
        )}

        {/* Bank */}
        <div className="mb-4">
          <div className="text-xs font-medium text-stone-700 mb-1">Bank</div>
          <div className="flex gap-1 flex-wrap">
            {bankCards.length === 0 && <span className="text-stone-400 italic text-sm">empty</span>}
            {bankCards.map((c) => (
              <div key={c.id} onClick={() => toggle(c.id)} className="cursor-pointer">
                <CardView card={c} variant="thumbnail" selected={selected.has(c.id)} />
              </div>
            ))}
          </div>
        </div>

        {/* Items */}
        <div className="mb-4">
          <div className="text-xs font-medium text-stone-700 mb-1">Items</div>
          {myPlayer.item_area.length === 0 && (
            <span className="text-stone-400 italic text-sm">no items</span>
          )}
          <div className="space-y-2">
            {myPlayer.item_area.map((col) => (
              <div key={col.column_id} className="border border-stone-200 rounded p-2">
                <div className="text-xs font-medium mb-1" style={{ color: colorHex(col.color) }}>
                  {colorHumanName(col.color)} {col.cards.length}/{ITEM_SETS[col.color].set_size}
                </div>
                <div className="flex gap-1 flex-wrap">
                  {col.cards.map((c) => {
                    const card = cardLookup(c.card_id);
                    if (!card) return null;
                    if (card.category === 'wild_item_any_color') {
                      return <CardView key={c.card_id} card={card} variant="thumbnail" />;
                    }
                    return (
                      <div key={c.card_id} onClick={() => toggle(c.card_id)} className="cursor-pointer">
                        <CardView card={card} variant="thumbnail" selected={selected.has(c.card_id)} />
                      </div>
                    );
                  })}
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="flex items-center justify-between border-t border-stone-200 pt-3">
          <div className="text-sm text-stone-600">
            Selected: <span className="font-bold">{totalSelected}</span> / debt {debtAmount}
            {totalSelected > debtAmount && <span className="text-red-600"> (overpaying — no change)</span>}
          </div>
          <button onClick={submit}
                  disabled={!canSubmit || working}
                  className="px-4 py-2 bg-emerald-700 text-white rounded font-medium disabled:opacity-50">
            {working ? 'Paying…' : 'Pay'}
          </button>
        </div>
      </div>
    </div>
  );
}
