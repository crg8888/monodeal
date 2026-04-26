import { useState } from 'react';
import { supabase } from '../lib/supabase';
import { getIdentity, isHost } from '../lib/identity';
import { broadcastStateChanged, useGameStore } from '../state/gameStore';
import type { Color, CharacterSlug } from '../types/game';

const CHARACTERS: Array<{
  slug: CharacterSlug;
  banner: string;
  bgClass: string;
}> = [
  { slug: 'harry',    banner: 'invisibility cloak — protect a color',     bgClass: 'bg-red-700' },
  { slug: 'draco',    banner: "father's name — bypass complete sets",     bgClass: 'bg-emerald-900' },
  { slug: 'hermione', banner: 'library — 4 plays per turn',                bgClass: 'bg-rose-800' },
  { slug: 'luna',     banner: 'open mind — draw 3 instead of 2',           bgClass: 'bg-blue-700' },
  { slug: 'cedric',   banner: 'resourceful — draw from discard',           bgClass: 'bg-yellow-600' },
];

const COLORS: Array<{ slug: Color; bg: string }> = [
  { slug: 'brown',       bg: 'bg-[#8B4513]' },
  { slug: 'light-blue',  bg: 'bg-[#87CEEB]' },
  { slug: 'pink',        bg: 'bg-[#FFC0CB]' },
  { slug: 'orange',      bg: 'bg-[#FFA500]' },
  { slug: 'light-green', bg: 'bg-[#90EE90]' },
  { slug: 'black',       bg: 'bg-[#1F2937]' },
  { slug: 'red',         bg: 'bg-[#DC2626]' },
  { slug: 'yellow',      bg: 'bg-[#FCD34D]' },
  { slug: 'dark-blue',   bg: 'bg-[#1E3A8A]' },
  { slug: 'dark-green',  bg: 'bg-[#14532D]' },
];

export function CharacterSelect() {
  const gameState = useGameStore((s) => s.gameState);
  const players = useGameStore((s) => s.players);
  const cards = useGameStore((s) => s.cards);
  const refresh = useGameStore((s) => s.refresh);
  const [pickingColor, setPickingColor] = useState(false);
  const [working, setWorking] = useState(false);

  const me = getIdentity();
  if (!me || !gameState) return null;
  const meIsHost = isHost(me, gameState.host_player_id);
  const myPlayer = players.find((p) => p.id === me.player_id);
  const myChar = myPlayer?.chosen_character ?? null;

  const characterCards = Object.values(cards).filter((c) => c.category === 'character');
  const findCharCard = (slug: CharacterSlug) =>
    characterCards.find((c) => c.slug === `character_${slug}`);

  const choose = async (slug: CharacterSlug) => {
    if (working) return;
    setWorking(true);
    const { data, error } = await supabase.rpc('choose_character', {
      p_actor_id: me.player_id,
      p_actor_token: me.player_token,
      p_slug: slug,
    });
    if (error) {
      alert(`Pick failed: ${error.message}`);
      setWorking(false);
      return;
    }
    await broadcastStateChanged();
    await refresh();
    if ((data as { needs_color: boolean })?.needs_color) {
      setPickingColor(true);
    }
    setWorking(false);
  };

  const pickColor = async (color: Color) => {
    if (working) return;
    setWorking(true);
    const { error } = await supabase.rpc('set_protected_color', {
      p_actor_id: me.player_id,
      p_actor_token: me.player_token,
      p_color: color,
    });
    if (error) {
      alert(`Color failed: ${error.message}`);
      setWorking(false);
      return;
    }
    setPickingColor(false);
    await broadcastStateChanged();
    await refresh();
    setWorking(false);
  };

  const startGame = async () => {
    setWorking(true);
    const { error } = await supabase.rpc('start_game', {
      p_actor_id: me.player_id,
      p_actor_token: me.player_token,
    });
    if (error) {
      alert(`Start failed: ${error.message}`);
      setWorking(false);
      return;
    }
    await broadcastStateChanged();
    await refresh();
    setWorking(false);
  };

  const allLocked =
    players.length >= 2 &&
    players.every(
      (p) =>
        p.chosen_character &&
        (p.chosen_character !== 'harry' || p.protected_color),
    );

  return (
    <div className="min-h-dvh bg-stone-50 p-4 sm:p-8">
      <div className="max-w-3xl mx-auto">
        <h1 className="text-2xl font-bold text-stone-900 mb-1">Pick your character</h1>
        <p className="text-stone-500 text-sm mb-6">
          Each character is unique. Once locked, you can't change.
        </p>

        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3 mb-6">
          {CHARACTERS.map(({ slug, banner, bgClass }) => {
            const takenBy = players.find((p) => p.chosen_character === slug);
            const isMe = takenBy?.id === me.player_id;
            const card = findCharCard(slug);
            return (
              <button
                key={slug}
                onClick={() => !takenBy && choose(slug)}
                disabled={!!takenBy || working}
                className={`relative rounded-lg overflow-hidden border-2 transition text-left ${
                  isMe
                    ? 'border-emerald-500 ring-2 ring-emerald-300'
                    : takenBy
                      ? 'border-stone-200 opacity-50 cursor-not-allowed'
                      : 'border-stone-200 hover:border-stone-400 cursor-pointer'
                }`}
              >
                <div className={`${bgClass} h-20 flex items-end p-2`}>
                  <div className="text-white font-bold capitalize">{slug}</div>
                </div>
                <div className="p-2 bg-white">
                  <div className="text-xs text-stone-700 line-clamp-2">{banner}</div>
                  {card?.flavor_text && (
                    <div className="text-[10px] italic text-stone-500 mt-1 line-clamp-2">
                      {card.flavor_text}
                    </div>
                  )}
                  {takenBy && (
                    <div className="text-xs text-stone-700 font-medium mt-1">
                      Taken by {isMe ? 'you' : takenBy.name}
                    </div>
                  )}
                </div>
              </button>
            );
          })}
        </div>

        <div className="bg-white border border-stone-200 rounded-lg p-3 mb-4">
          <div className="text-xs text-stone-500 mb-2">Lock status</div>
          <ul className="space-y-1">
            {players.map((p) => {
              const ready =
                p.chosen_character &&
                (p.chosen_character !== 'harry' || p.protected_color);
              return (
                <li key={p.id} className="flex items-center gap-2 text-sm">
                  <span
                    className={`w-2 h-2 rounded-full ${
                      ready ? 'bg-emerald-500' : 'bg-stone-300'
                    }`}
                  />
                  <span className="font-medium text-stone-900">{p.name}</span>
                  <span className="text-stone-500">
                    {p.chosen_character
                      ? `→ ${p.chosen_character}${
                          p.chosen_character === 'harry' && p.protected_color
                            ? ` (${p.protected_color})`
                            : ''
                        }`
                      : '— picking…'}
                  </span>
                </li>
              );
            })}
          </ul>
        </div>

        {meIsHost && (
          <button
            onClick={startGame}
            disabled={!allLocked || working}
            className="w-full px-4 py-3 bg-emerald-700 text-white rounded hover:bg-emerald-600 disabled:opacity-50 disabled:cursor-not-allowed font-medium"
          >
            {!allLocked ? 'Waiting for everyone to lock…' : `Start game · ${players.length} players`}
          </button>
        )}
        {!meIsHost && allLocked && (
          <div className="text-sm text-stone-500 text-center">Waiting for host to start…</div>
        )}

        {pickingColor && myChar === 'harry' && (
          <div className="fixed inset-0 bg-black/50 flex items-center justify-center p-4 z-50">
            <div className="bg-white rounded-lg max-w-md w-full p-6">
              <h2 className="text-lg font-bold text-stone-900 mb-1">
                Pick the color you'll protect
              </h2>
              <p className="text-sm text-stone-500 mb-4">
                Opponents can't take or discard your items of this color (while you're not petrified).
              </p>
              <div className="grid grid-cols-5 gap-2">
                {COLORS.map(({ slug, bg }) => (
                  <button
                    key={slug}
                    onClick={() => pickColor(slug)}
                    disabled={working}
                    className={`${bg} h-14 rounded border-2 border-stone-200 hover:border-stone-900 disabled:opacity-50`}
                    title={slug}
                  />
                ))}
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
