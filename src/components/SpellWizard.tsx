import { useState } from 'react';
import { supabase } from '../lib/supabase';
import { getIdentity } from '../lib/identity';
import { broadcastStateChanged, useGameStore } from '../state/gameStore';
import { Card as CardView, colorHex } from './Card';
import { ITEM_SETS, isColumnComplete, colorHumanName } from '../lib/rules';
import type { Card as CardData, Color, ItemColumn, Player } from '../types/game';

type Step =
  | { kind: 'pick_opponent' }
  | { kind: 'pick_target_item'; targetId: string }
  | { kind: 'pick_my_item'; targetId: string; targetCardId: string }
  | { kind: 'pick_complete_color'; targetId: string }
  | { kind: 'pick_discard_card' }
  | { kind: 'pick_wild_color'; reparoCardId: string };

export function SpellWizard(props: {
  card: CardData;
  onClose: () => void;
  onCast: () => void;
}) {
  const me = getIdentity()!;
  const players = useGameStore((s) => s.players);
  const cards = useGameStore((s) => s.cards);
  const cardLookup = useGameStore((s) => s.cardLookup);
  const refresh = useGameStore((s) => s.refresh);
  const fetchMyHand = useGameStore((s) => s.fetchMyHand);
  const gameState = useGameStore((s) => s.gameState);
  const opponents = players.filter((p) => p.id !== me.player_id);

  const [step, setStep] = useState<Step | null>(initialStep(props.card.spell_effect));
  const [working, setWorking] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function initialStep(effect: string | null | undefined): Step | null {
    switch (effect) {
      case 'geminio': return null; // immediate
      case 'reparo': return { kind: 'pick_discard_card' };
      case 'petrificus_totalus':
      case 'levicorpus':
      case 'wingardium_leviosa':
      case 'confundo':
        return { kind: 'pick_opponent' };
      case 'obliviate':
        return { kind: 'pick_opponent' };
      default:
        return null;
    }
  }

  const cast = async (params: Record<string, unknown> = {}) => {
    setWorking(true);
    setError(null);
    const { error: err } = await supabase.rpc('cast_spell', {
      p_actor_id: me.player_id,
      p_actor_token: me.player_token,
      p_card_id: props.card.id,
      p_params: params,
    });
    if (err) {
      const msg: Record<string, string> = {
        harry_protected: 'Target is protected by Harry.',
        cannot_take_from_complete: 'Items in complete sets are protected (Draco bypasses).',
        cannot_take_from_complete_target: "Target's item is in a complete set (Draco bypasses).",
        cannot_take_from_complete_self: 'Your item is in a complete set.',
        no_complete_column: 'Target has no complete set of that color.',
      };
      setError(msg[err.message] ?? err.message);
      setWorking(false);
      return;
    }
    await broadcastStateChanged();
    await refresh();
    await fetchMyHand(me.player_id, me.player_token);
    props.onCast();
  };

  // Geminio fires automatically on mount.
  if (props.card.spell_effect === 'geminio' && !working && !error && step === null) {
    void cast();
  }

  const close = () => props.onClose();

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center p-4 z-50" onClick={close}>
      <div className="bg-white rounded-lg max-w-2xl w-full p-6 max-h-[90vh] overflow-auto"
           onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between mb-3">
          <div>
            <div className="text-xs text-stone-500">Casting</div>
            <h2 className="text-lg font-bold text-stone-900">{props.card.title}</h2>
          </div>
          <button onClick={close} className="text-stone-400 hover:text-stone-600 text-2xl leading-none">×</button>
        </div>

        {error && (
          <div className="mb-3 p-2 bg-red-50 border border-red-200 text-red-900 text-sm rounded">
            {error}
            <button onClick={() => setError(null)}
                    className="ml-2 underline text-xs">dismiss</button>
          </div>
        )}

        {step?.kind === 'pick_opponent' && (
          <PickOpponent opponents={opponents} onPick={(id) => {
            if (props.card.spell_effect === 'petrificus_totalus') {
              void cast({ target_player_id: id });
            } else if (props.card.spell_effect === 'obliviate') {
              setStep({ kind: 'pick_complete_color', targetId: id });
            } else {
              setStep({ kind: 'pick_target_item', targetId: id });
            }
          }} />
        )}

        {step?.kind === 'pick_target_item' && (
          <PickItem
            player={players.find((p) => p.id === step.targetId)!}
            cardLookup={cardLookup}
            label="Pick the opponent's item"
            onPick={(itemId) => {
              if (props.card.spell_effect === 'confundo') {
                setStep({ kind: 'pick_my_item', targetId: step.targetId, targetCardId: itemId });
              } else {
                void cast({
                  target_player_id: step.targetId,
                  target_card_id: itemId,
                });
              }
            }}
          />
        )}

        {step?.kind === 'pick_my_item' && (
          <PickItem
            player={players.find((p) => p.id === me.player_id)!}
            cardLookup={cardLookup}
            label="Pick the item to give in exchange"
            onPick={(myId) => {
              void cast({
                target_player_id: step.targetId,
                target_card_id: step.targetCardId,
                my_card_id: myId,
              });
            }}
          />
        )}

        {step?.kind === 'pick_complete_color' && (
          <PickCompleteColor
            player={players.find((p) => p.id === step.targetId)!}
            cardLookup={cardLookup}
            onPick={(color) => void cast({
              target_player_id: step.targetId,
              target_color: color,
            })}
          />
        )}

        {step?.kind === 'pick_discard_card' && (
          <PickDiscardCard
            discardPile={gameState!.discard_pile}
            cards={cards}
            onPick={(cid) => {
              const card = cards[cid];
              if (
                card?.category === 'wild_item_two_color' ||
                card?.category === 'wild_item_any_color'
              ) {
                setStep({ kind: 'pick_wild_color', reparoCardId: cid });
              } else {
                void cast({ from_discard_card_id: cid });
              }
            }}
          />
        )}

        {step?.kind === 'pick_wild_color' && (() => {
          const wild = cards[step.reparoCardId];
          const colors = (wild?.colors ?? []) as Color[];
          return (
            <div>
              <div className="font-medium mb-2">Pick a color for the wild</div>
              <div className="flex gap-2 flex-wrap">
                {colors.map((c) => (
                  <button key={c}
                          onClick={() => void cast({ from_discard_card_id: step.reparoCardId, dest_color: c })}
                          className="h-12 w-12 rounded border-2 border-stone-200 hover:border-stone-900"
                          style={{ background: colorHex(c) }} />
                ))}
              </div>
            </div>
          );
        })()}

        {working && <div className="text-center text-stone-500 text-sm py-4">Casting…</div>}
      </div>
    </div>
  );
}

function PickOpponent(props: { opponents: Player[]; onPick: (id: string) => void }) {
  return (
    <div>
      <div className="text-sm font-medium text-stone-700 mb-2">Pick an opponent</div>
      <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
        {props.opponents.map((p) => (
          <button key={p.id} onClick={() => props.onPick(p.id)}
                  className="p-3 bg-white border border-stone-200 rounded hover:border-stone-900 text-left">
            <div className="font-medium text-stone-900">{p.name}</div>
            <div className="text-xs text-stone-500 capitalize">{p.chosen_character ?? '—'}</div>
          </button>
        ))}
      </div>
    </div>
  );
}

function PickItem(props: {
  player: Player;
  cardLookup: (id: string) => CardData | undefined;
  label: string;
  onPick: (cardId: string) => void;
}) {
  const cols = props.player.item_area;
  return (
    <div>
      <div className="text-sm font-medium text-stone-700 mb-2">{props.label} ({props.player.name})</div>
      {cols.length === 0 && <div className="text-stone-400 italic">no items</div>}
      <div className="space-y-2">
        {cols.map((col: ItemColumn) => (
          <div key={col.column_id} className="border border-stone-200 rounded p-2">
            <div className="text-xs font-medium mb-1" style={{ color: colorHex(col.color) }}>
              {colorHumanName(col.color)} {col.cards.length}/{ITEM_SETS[col.color].set_size}
              {isColumnComplete(col, props.cardLookup) && <span> — complete</span>}
            </div>
            <div className="flex gap-1 flex-wrap">
              {col.cards.map((c) => {
                const card = props.cardLookup(c.card_id);
                if (!card) return null;
                return (
                  <div key={c.card_id} onClick={() => props.onPick(c.card_id)} className="cursor-pointer">
                    <CardView card={card} variant="compressed" />
                  </div>
                );
              })}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function PickCompleteColor(props: {
  player: Player;
  cardLookup: (id: string) => CardData | undefined;
  onPick: (color: Color) => void;
}) {
  const completes = props.player.item_area
    .filter((col) => isColumnComplete(col, props.cardLookup))
    .map((col) => col.color);
  return (
    <div>
      <div className="text-sm font-medium text-stone-700 mb-2">
        Pick a complete set to take from {props.player.name}
      </div>
      {completes.length === 0 && <div className="text-stone-400 italic">no complete sets</div>}
      <div className="flex gap-2 flex-wrap">
        {completes.map((c) => (
          <button key={c} onClick={() => props.onPick(c)}
                  className="px-4 py-2 bg-amber-100 border-2 border-amber-400 rounded font-medium hover:bg-amber-200 capitalize">
            {colorHumanName(c)}
          </button>
        ))}
      </div>
    </div>
  );
}

function PickDiscardCard(props: {
  discardPile: string[];
  cards: Record<string, CardData>;
  onPick: (cardId: string) => void;
}) {
  if (props.discardPile.length === 0) {
    return <div className="text-stone-400 italic">discard is empty</div>;
  }
  return (
    <div>
      <div className="text-sm font-medium text-stone-700 mb-2">Pick a card from the discard pile</div>
      <div className="grid grid-cols-3 sm:grid-cols-5 gap-2 max-h-96 overflow-auto">
        {props.discardPile.map((id) => {
          const card = props.cards[id];
          if (!card) return null;
          return (
            <div key={id} onClick={() => props.onPick(id)} className="cursor-pointer">
              <CardView card={card} variant="full" />
            </div>
          );
        })}
      </div>
    </div>
  );
}
