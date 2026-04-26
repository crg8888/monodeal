import { supabase } from './supabase';

// Channel taxonomy per docs/lovable-prompt-v5.md lines 67-74:
//   game:public         broadcasts public state after every RPC.
//   game:private:{pid}  broadcasts that player's hand only.
//
// Slice 0 doesn't broadcast yet; this is a scaffold for Slice 1+.

export function subscribePublic(onUpdate: (payload: unknown) => void) {
  const channel = supabase.channel('game:public');
  channel.on('broadcast', { event: 'state' }, (msg) => onUpdate(msg.payload));
  channel.subscribe();
  return () => {
    supabase.removeChannel(channel);
  };
}

export function subscribePrivate(playerId: string, onHand: (payload: unknown) => void) {
  const channel = supabase.channel(`game:private:${playerId}`);
  channel.on('broadcast', { event: 'hand' }, (msg) => onHand(msg.payload));
  channel.subscribe();
  return () => {
    supabase.removeChannel(channel);
  };
}
