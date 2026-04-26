import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { getIdentity } from '../lib/identity';
import { broadcastStateChanged, useGameStore } from '../state/gameStore';
import { Card as CardView, colorHex } from '../components/Card';
import { SpellWizard } from '../components/SpellWizard';
import { PaymentModal } from '../components/PaymentModal';
import { isHost } from '../lib/identity';
import { ITEM_SETS, isColumnComplete, colorHumanName } from '../lib/rules';
import type { Color, Player, Card as CardData, ItemColumn } from '../types/game';

export function GameTable() {
  const gameState = useGameStore((s) => s.gameState);
  const players = useGameStore((s) => s.players);
  const cards = useGameStore((s) => s.cards);
  const myHand = useGameStore((s) => s.myHand);
  const fetchMyHand = useGameStore((s) => s.fetchMyHand);
  const refresh = useGameStore((s) => s.refresh);
  const cardLookup = useGameStore((s) => s.cardLookup);

  const me = getIdentity();
  const [working, setWorking] = useState(false);
  const [colorPick, setColorPick] = useState<{ card: CardData } | null>(null);
  const [spellChoice, setSpellChoice] = useState<{ card: CardData } | null>(null);
  const [castingSpell, setCastingSpell] = useState<CardData | null>(null);
  const [discardPicker, setDiscardPicker] = useState<{ excess: number } | null>(null);
  const [discardSelection, setDiscardSelection] = useState<Set<string>>(new Set());
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!me) return;
    void fetchMyHand(me.player_id, me.player_token);
  }, [me?.player_id, gameState?.version]);

  if (!gameState || !me) return null;
  const myPlayer = players.find((p) => p.id === me.player_id);
  if (!myPlayer) return null;

  const isMyTurn = gameState.turn_player_id === me.player_id;
  const hasDrawn = gameState.has_drawn_this_turn;
  const playsLeft = gameState.plays_allowed_this_turn - gameState.plays_this_turn;
  const opponents = players.filter((p) => p.id !== me.player_id);

  const callRpc = async (name: string, params: Record<string, unknown>) => {
    setWorking(true);
    setError(null);
    const { data, error: err } = await supabase.rpc(name, params);
    if (err) {
      setError(err.message);
      setWorking(false);
      return null;
    }
    await broadcastStateChanged();
    await refresh();
    if (me) await fetchMyHand(me.player_id, me.player_token);
    setWorking(false);
    return data;
  };

  const draw = (fromDiscard = false) => callRpc('start_turn', {
    p_actor_id: me.player_id, p_actor_token: me.player_token,
    p_from_discard: fromDiscard,
  });

  const [petrificusPicker, setPetrificusPicker] = useState(false);
  const [petrificusSelection, setPetrificusSelection] = useState<Set<string>>(new Set());
  const removePetrificus = async () => {
    if (petrificusSelection.size === 0) return;
    const result = await callRpc('remove_petrificus', {
      p_actor_id: me.player_id, p_actor_token: me.player_token,
      p_card_ids: Array.from(petrificusSelection),
    });
    if (result) {
      setPetrificusPicker(false);
      setPetrificusSelection(new Set());
    }
  };

  const playToBank = async (cardId: string) => {
    await callRpc('play_to_bank', {
      p_actor_id: me.player_id, p_actor_token: me.player_token, p_card_id: cardId,
    });
  };

  const playItemAs = async (cardId: string, color: Color) => {
    setColorPick(null);
    const card = cards[cardId];
    const rpc =
      card?.category === 'wild_item_two_color' || card?.category === 'wild_item_any_color'
        ? 'play_wild_item'
        : 'play_item';
    await callRpc(rpc, {
      p_actor_id: me.player_id, p_actor_token: me.player_token,
      p_card_id: cardId, p_color: color, p_target_column_id: null,
    });
  };

  const endTurn = async () => {
    const result = await callRpc('end_turn', {
      p_actor_id: me.player_id, p_actor_token: me.player_token,
      p_discard_card_ids: [],
    });
    if (result && (result as { status?: string }).status === 'must_discard') {
      setDiscardPicker({ excess: (result as { excess: number }).excess });
      setDiscardSelection(new Set());
    }
  };

  const submitDiscard = async () => {
    if (!discardPicker) return;
    if (discardSelection.size !== discardPicker.excess) return;
    const result = await callRpc('end_turn', {
      p_actor_id: me.player_id, p_actor_token: me.player_token,
      p_discard_card_ids: Array.from(discardSelection),
    });
    if (result && !(result as { status?: string }).status) {
      setDiscardPicker(null);
      setDiscardSelection(new Set());
    }
  };

  const onCardClick = (card: CardData) => {
    if (!isMyTurn) return;
    if (!hasDrawn) {
      setError('Draw first.');
      return;
    }
    if (playsLeft <= 0) {
      setError('No plays left this turn — end your turn.');
      return;
    }
    if (card.category === 'point') {
      void playToBank(card.id);
      return;
    }
    if (card.category === 'spell') {
      // Spell: bank or cast (Slice 5). Protego is reactive only, can't cast.
      if (card.spell_effect === 'protego') {
        void playToBank(card.id);
        return;
      }
      setSpellChoice({ card });
      return;
    }
    if (card.category === 'item') {
      const colors = card.colors ?? [];
      if (colors.length === 1) {
        void playItemAs(card.id, colors[0] as Color);
      } else {
        setColorPick({ card });
      }
      return;
    }
    if (card.category === 'wild_item_two_color' || card.category === 'wild_item_any_color') {
      setColorPick({ card });
    }
  };

  const winnerPlayer = gameState.winner_player_id
    ? players.find((p) => p.id === gameState.winner_player_id)
    : null;
  const meIsHost = isHost(me, gameState.host_player_id);
  const [logOpen, setLogOpen] = useState(false);
  const [hostOpen, setHostOpen] = useState(false);

  const newGame = async () => {
    await callRpc('reset_to_lobby', {
      p_actor_id: me.player_id, p_actor_token: me.player_token,
    });
  };
  const forceEnd = async () => {
    if (!confirm('Force-end the current turn?')) return;
    await callRpc('host_force_end_turn', {
      p_actor_id: me.player_id, p_actor_token: me.player_token,
    });
  };

  const myActiveDebt = gameState.payment_queue.find(
    (d) => d.debtor_id === me.player_id && d.status === 'active',
  );
  const someoneElsePaying = gameState.payment_queue.find((d) => d.status === 'active');

  return (
    <div className="min-h-dvh bg-stone-100 flex flex-col">
      {winnerPlayer && (
        <div className="bg-amber-400 text-amber-950 p-4 text-center">
          <div className="font-bold text-lg">🎉 {winnerPlayer.name} wins!</div>
          {meIsHost && (
            <button onClick={newGame}
                    className="mt-2 px-4 py-1.5 bg-amber-950 text-amber-100 rounded text-sm font-medium hover:bg-amber-800">
              New game (same players)
            </button>
          )}
        </div>
      )}

      {/* Opponent zones */}
      <div className="flex-shrink-0 p-2 sm:p-4 grid gap-2 sm:gap-3"
           style={{ gridTemplateColumns: `repeat(${Math.max(1, opponents.length)}, minmax(0, 1fr))` }}>
        {opponents.map((p) => (
          <OpponentZone key={p.id} player={p} cardLookup={cardLookup}
            isTurn={p.id === gameState.turn_player_id} />
        ))}
      </div>

      {/* Center: deck + discard + status */}
      <div className="flex-shrink-0 px-4 py-2 bg-stone-200 border-y border-stone-300 flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3 text-sm text-stone-700">
          <div>Deck: <span className="font-mono font-bold">{gameState.deck_count}</span></div>
          <div>Discard: <span className="font-mono font-bold">{gameState.discard_pile.length}</span></div>
          <div>Turn: <span className="font-bold">{players.find((p) => p.id === gameState.turn_player_id)?.name ?? '—'}</span></div>
        </div>
        <div className="text-sm text-stone-700">
          {isMyTurn
            ? hasDrawn
              ? <>Plays: <span className="font-bold">{playsLeft}/{gameState.plays_allowed_this_turn}</span></>
              : <span className="font-medium">Your turn — draw first</span>
            : <span className="text-stone-500">Waiting…</span>}
        </div>
      </div>

      {/* My zone */}
      <div className="flex-1 p-2 sm:p-4 overflow-auto">
        <MyZone player={myPlayer} cardLookup={cardLookup} />
      </div>

      {/* Hand */}
      <div className="flex-shrink-0 bg-white border-t border-stone-300 p-2 sm:p-3">
        <div className="flex items-center justify-between mb-2">
          <div className="text-xs text-stone-500">Your hand · {myHand.length} cards</div>
          <div className="flex gap-2">
            {isMyTurn && !hasDrawn && (
              <>
                <button onClick={() => draw(false)} disabled={working}
                        className="px-3 py-1.5 bg-emerald-700 text-white rounded text-sm font-medium hover:bg-emerald-600 disabled:opacity-50">
                  Draw {
                    myPlayer.hand_count === 0
                      ? 5
                      : (myPlayer.chosen_character === 'luna' && !myPlayer.petrified ? 3 : 2)
                  }
                </button>
                {myPlayer.chosen_character === 'cedric' && !myPlayer.petrified
                 && gameState.discard_pile.length > 0 && (
                  <button onClick={() => draw(true)} disabled={working}
                          className="px-3 py-1.5 bg-yellow-600 text-white rounded text-sm font-medium hover:bg-yellow-500 disabled:opacity-50">
                    Draw (top of discard)
                  </button>
                )}
              </>
            )}
            {isMyTurn && myPlayer.petrified && (
              <button onClick={() => setPetrificusPicker(true)} disabled={working}
                      className="px-3 py-1.5 bg-purple-700 text-white rounded text-sm font-medium hover:bg-purple-600 disabled:opacity-50">
                Break Petrificus
              </button>
            )}
            {isMyTurn && hasDrawn && (
              <button onClick={endTurn} disabled={working}
                      className="px-3 py-1.5 bg-stone-900 text-white rounded text-sm font-medium hover:bg-stone-700 disabled:opacity-50">
                End turn
              </button>
            )}
          </div>
        </div>
        <div className="flex gap-2 overflow-x-auto pb-1">
          {myHand.map((id) => {
            const card = cards[id];
            if (!card) return null;
            return (
              <div key={id} onClick={() => onCardClick(card)}
                   className="flex-shrink-0 cursor-pointer hover:scale-105 transition">
                <CardView card={card} variant="full" />
              </div>
            );
          })}
        </div>
      </div>

      {error && (
        <div onClick={() => setError(null)}
             className="fixed bottom-4 right-4 max-w-sm p-3 bg-red-100 border border-red-300 text-red-900 text-sm rounded shadow cursor-pointer z-30">
          {error}
        </div>
      )}

      {/* Game log toggle (top-right) */}
      <button onClick={() => setLogOpen(!logOpen)}
              className="fixed top-2 right-2 z-20 px-2 py-1 bg-white border border-stone-300 rounded text-xs text-stone-700 hover:bg-stone-50">
        {logOpen ? 'hide log' : `log (${gameState.log.length})`}
      </button>

      {logOpen && (
        <div className="fixed top-10 right-2 z-20 w-72 max-h-96 overflow-auto bg-white border border-stone-300 rounded shadow-lg p-2 text-xs">
          {[...gameState.log].slice(-30).reverse().map((l, i) => (
            <div key={i} className="py-0.5 border-b border-stone-100">
              <span className="text-stone-400 mr-1">[{l.kind}]</span>
              {l.text}
            </div>
          ))}
        </div>
      )}

      {/* Host sidebar (only host sees) */}
      {meIsHost && (
        <>
          <button onClick={() => setHostOpen(!hostOpen)}
                  className="fixed top-2 left-2 z-20 px-2 py-1 bg-amber-100 border border-amber-300 rounded text-xs text-amber-900 hover:bg-amber-200 font-medium">
            {hostOpen ? 'hide host' : '★ host'}
          </button>
          {hostOpen && (
            <div className="fixed top-10 left-2 z-20 w-56 bg-white border border-amber-200 rounded shadow-lg p-2 space-y-1">
              <div className="text-xs text-stone-500 mb-1">Host controls</div>
              <button onClick={forceEnd}
                      className="w-full px-2 py-1.5 bg-stone-200 hover:bg-stone-300 rounded text-xs text-left">
                Force-end current turn
              </button>
              <button onClick={async () => {
                if (!confirm('Reset and start a new game with same players?')) return;
                await newGame();
              }}
                      className="w-full px-2 py-1.5 bg-emerald-100 hover:bg-emerald-200 rounded text-xs text-left">
                Restart (same players)
              </button>
              <button onClick={async () => {
                if (!confirm('Full reset — kick everyone back to name entry?')) return;
                await callRpc('host_full_reset', {
                  p_actor_id: me.player_id, p_actor_token: me.player_token,
                });
              }}
                      className="w-full px-2 py-1.5 bg-red-100 hover:bg-red-200 rounded text-xs text-left">
                Full reset (kick all)
              </button>
            </div>
          )}
        </>
      )}

      {colorPick && (
        <Modal onClose={() => setColorPick(null)}>
          <div className="text-lg font-bold mb-2">Play {colorPick.card.title} as…</div>
          <div className="flex gap-2 flex-wrap">
            {(colorPick.card.colors ?? []).map((c) => (
              <button key={c} onClick={() => playItemAs(colorPick.card.id, c as Color)}
                      className="h-12 w-12 rounded border-2 border-stone-200 hover:border-stone-900"
                      style={{ background: colorHex(c) }} title={c} />
            ))}
          </div>
        </Modal>
      )}

      {spellChoice && (
        <Modal onClose={() => setSpellChoice(null)}>
          <div className="text-lg font-bold mb-1">{spellChoice.card.title}</div>
          <p className="text-sm text-stone-500 mb-4">
            Bank for cash {spellChoice.card.cash_value ?? 0}, or cast for the effect?
          </p>
          <div className="flex gap-2">
            <button
              onClick={() => { void playToBank(spellChoice.card.id); setSpellChoice(null); }}
              className="flex-1 px-4 py-2 bg-stone-200 text-stone-900 rounded font-medium hover:bg-stone-300">
              Bank ({spellChoice.card.cash_value ?? 0})
            </button>
            <button
              onClick={() => { setCastingSpell(spellChoice.card); setSpellChoice(null); }}
              className="flex-1 px-4 py-2 bg-emerald-700 text-white rounded font-medium hover:bg-emerald-600">
              Cast spell
            </button>
          </div>
        </Modal>
      )}

      {castingSpell && (
        <SpellWizard
          card={castingSpell}
          onClose={() => setCastingSpell(null)}
          onCast={() => setCastingSpell(null)}
        />
      )}

      {myActiveDebt && <PaymentModal debt={myActiveDebt} />}

      {petrificusPicker && (
        <Modal onClose={() => setPetrificusPicker(false)}>
          <div className="text-lg font-bold mb-1">Break Petrificus</div>
          <p className="text-sm text-stone-500 mb-3">
            Discard ≥ 10 cash from your bank. The Petrificus card goes with it.
            Selected: <span className="font-bold">
              {Array.from(petrificusSelection).reduce((s, id) => s + (cards[id]?.cash_value ?? 0), 0)}
            </span> / 10
          </p>
          <div className="grid grid-cols-3 sm:grid-cols-5 gap-2 max-h-80 overflow-auto mb-4">
            {myPlayer.bank.map((id) => {
              const card = cards[id];
              if (!card) return null;
              if (card.spell_effect === 'petrificus_totalus') return null; // hide attached
              const sel = petrificusSelection.has(id);
              return (
                <div key={id} onClick={() => {
                  const next = new Set(petrificusSelection);
                  if (sel) next.delete(id); else next.add(id);
                  setPetrificusSelection(next);
                }} className="cursor-pointer">
                  <CardView card={card} variant="compressed" selected={sel} />
                </div>
              );
            })}
          </div>
          <button
            onClick={removePetrificus}
            disabled={
              Array.from(petrificusSelection).reduce((s, id) => s + (cards[id]?.cash_value ?? 0), 0) < 10
              || working
            }
            className="w-full px-4 py-2 bg-purple-700 text-white rounded font-medium disabled:opacity-50">
            Break Petrificus
          </button>
        </Modal>
      )}
      {!myActiveDebt && someoneElsePaying && (
        <div className="fixed bottom-4 left-4 bg-amber-100 border border-amber-300 text-amber-900 text-sm px-3 py-2 rounded shadow">
          Waiting for {players.find((p) => p.id === someoneElsePaying.debtor_id)?.name ?? 'someone'} to pay {someoneElsePaying.amount}…
        </div>
      )}

      {discardPicker && (
        <Modal onClose={() => setDiscardPicker(null)}>
          <div className="text-lg font-bold mb-1">
            Discard {discardPicker.excess} card{discardPicker.excess > 1 ? 's' : ''}
          </div>
          <p className="text-sm text-stone-500 mb-3">Hand limit is 7 at end of turn.</p>
          <div className="grid grid-cols-3 sm:grid-cols-4 gap-2 max-h-96 overflow-auto mb-4">
            {myHand.map((id) => {
              const card = cards[id];
              if (!card) return null;
              const selected = discardSelection.has(id);
              return (
                <div key={id} onClick={() => {
                  const next = new Set(discardSelection);
                  if (selected) next.delete(id); else next.add(id);
                  setDiscardSelection(next);
                }} className="cursor-pointer">
                  <CardView card={card} variant="compressed" selected={selected} />
                </div>
              );
            })}
          </div>
          <button onClick={submitDiscard}
                  disabled={discardSelection.size !== discardPicker.excess}
                  className="w-full px-4 py-2 bg-emerald-700 text-white rounded font-medium disabled:opacity-50">
            Confirm ({discardSelection.size}/{discardPicker.excess})
          </button>
        </Modal>
      )}
    </div>
  );
}

function Modal(props: { children: React.ReactNode; onClose: () => void }) {
  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center p-4 z-50"
         onClick={props.onClose}>
      <div onClick={(e) => e.stopPropagation()}
           className="bg-white rounded-lg max-w-md w-full p-6 max-h-[90vh] overflow-auto">
        {props.children}
      </div>
    </div>
  );
}

function OpponentZone(props: {
  player: Player;
  cardLookup: (id: string) => CardData | undefined;
  isTurn: boolean;
}) {
  const { player, cardLookup, isTurn } = props;
  const bankCards = player.bank.map(cardLookup).filter(Boolean) as CardData[];
  const bankCash = bankCards.reduce((s, c) => s + (c.cash_value ?? 0), 0);
  return (
    <div className={`bg-white rounded p-2 border-2 ${isTurn ? 'border-emerald-500' : 'border-stone-200'}`}>
      <div className="flex items-center justify-between mb-1">
        <span className="text-xs font-medium text-stone-900 truncate">{player.name}</span>
        <div className="flex items-center gap-1">
          {player.petrified && (
            <span className="text-[9px] px-1 bg-purple-200 text-purple-900 rounded font-bold">PETRIFIED</span>
          )}
          <span className="text-[10px] text-stone-500 capitalize">
            {player.chosen_character ?? '—'}
          </span>
        </div>
      </div>
      <div className="text-[10px] text-stone-500 mb-1">
        Hand {player.hand_count} · Bank {bankCash}
      </div>
      <ItemArea columns={player.item_area} cardLookup={cardLookup} compact />
    </div>
  );
}

function MyZone(props: {
  player: Player;
  cardLookup: (id: string) => CardData | undefined;
}) {
  const { player, cardLookup } = props;
  const bankCards = player.bank.map(cardLookup).filter(Boolean) as CardData[];
  const bankCash = bankCards.reduce((s, c) => s + (c.cash_value ?? 0), 0);
  return (
    <div className="space-y-3">
      <div className="bg-white rounded p-2 border border-stone-200">
        <div className="text-xs text-stone-500 mb-1">Items</div>
        <ItemArea columns={player.item_area} cardLookup={cardLookup} />
      </div>
      <div className="bg-white rounded p-2 border border-stone-200">
        <div className="text-xs text-stone-500 mb-1">Bank — {bankCash} cash</div>
        <div className="flex gap-1 flex-wrap">
          {bankCards.length === 0 && <div className="text-stone-400 text-sm italic">empty</div>}
          {bankCards.map((c) => (
            <div key={c.id}><CardView card={c} variant="thumbnail" /></div>
          ))}
        </div>
      </div>
    </div>
  );
}

function ItemArea(props: {
  columns: ItemColumn[];
  cardLookup: (id: string) => CardData | undefined;
  compact?: boolean;
}) {
  if (props.columns.length === 0) {
    return <div className="text-stone-400 text-xs italic">no items yet</div>;
  }
  return (
    <div className="flex gap-1 flex-wrap">
      {props.columns.map((col) => {
        const set = ITEM_SETS[col.color];
        const complete = isColumnComplete(col, props.cardLookup);
        return (
          <div key={col.column_id}
               className={`rounded px-1 py-1 ${complete ? 'bg-amber-100 border border-amber-400' : 'bg-stone-50 border border-stone-200'}`}>
            <div className="flex items-center gap-1 mb-0.5 text-[9px] font-medium" style={{ color: complete ? '#92400e' : undefined }}>
              <span className="inline-block w-2 h-2 rounded-full" style={{ background: colorHex(col.color) }} />
              {colorHumanName(col.color)} {col.cards.length}/{set.set_size}
              {complete && <span className="font-bold">✓</span>}
            </div>
            <div className="flex gap-0.5">
              {col.cards.map((c) => {
                const card = props.cardLookup(c.card_id);
                if (!card) return null;
                return <CardView key={c.card_id} card={card} variant={props.compact ? 'thumbnail' : 'compressed'} />;
              })}
            </div>
          </div>
        );
      })}
    </div>
  );
}
