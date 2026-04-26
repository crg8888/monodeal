import type { Card as CardData } from '../types/game';

/**
 * Local fallback type used only if `../types/game` doesn't yet export `Card`.
 * Kept narrow — just the fields this component reads.
 */
export interface CardLike {
  id: string;
  slug: string;
  category:
    | 'point'
    | 'item'
    | 'wild_item_two_color'
    | 'wild_item_any_color'
    | 'spell'
    | 'character';
  title: string;
  cash_value?: number | null;
  colors?: string[];
  spell_effect?: string | null;
  rules_text?: string | null;
  art_asset_url?: string | null;
}

export type Variant = 'full' | 'compressed' | 'thumbnail';

export interface Props {
  card: CardData;
  variant?: Variant;
  faceDown?: boolean;
  selected?: boolean;
  onClick?: () => void;
}

/**
 * Map a Monodeal color slug to a hex value.
 * Exported so other UI bits (column headers, color pickers, etc.) can reuse it.
 */
export function colorHex(color: string): string {
  switch (color) {
    case 'brown':
      return '#8B4513';
    case 'light-blue':
      return '#87CEEB';
    case 'pink':
      return '#FFC0CB';
    case 'orange':
      return '#FFA500';
    case 'light-green':
      return '#90EE90';
    case 'black':
      return '#1F2937';
    case 'red':
      return '#DC2626';
    case 'yellow':
      return '#FCD34D';
    case 'dark-blue':
      return '#1E3A8A';
    case 'dark-green':
      return '#14532D';
    default:
      return '#6B7280'; // gray-500 fallback
  }
}

const ALL_COLORS = [
  'brown',
  'light-blue',
  'pink',
  'orange',
  'light-green',
  'black',
  'red',
  'yellow',
  'dark-blue',
  'dark-green',
];

const RAINBOW_GRADIENT = `linear-gradient(90deg, ${ALL_COLORS.map(colorHex).join(', ')})`;

/** Pick a glyph that fits the spell. Pure cosmetic until real art lands. */
function spellGlyph(spell_effect?: string | null): string {
  if (!spell_effect) return '🪄';
  if (spell_effect.startsWith('accio')) return '🧲';
  if (spell_effect === 'geminio') return '✨';
  if (spell_effect === 'reparo') return '🔧';
  if (spell_effect === 'alohomora') return '🔓';
  if (spell_effect === 'confundo') return '💫';
  if (spell_effect === 'stupefy') return '⚔️';
  if (spell_effect === 'levicorpus') return '🪂';
  if (spell_effect === 'protego') return '🛡';
  if (spell_effect === 'wingardium_leviosa') return '🪶';
  if (spell_effect === 'petrificus_totalus') return '🗿';
  if (spell_effect === 'obliviate') return '🌫️';
  return '🪄';
}

function variantSize(variant: Variant): string {
  switch (variant) {
    case 'thumbnail':
      return 'w-12 h-16';
    case 'compressed':
      // half-height of full; works as overlapping fan strip
      return 'w-32 h-20 sm:w-40 sm:h-24';
    case 'full':
    default:
      return 'w-32 h-44 sm:w-40 sm:h-56';
  }
}

interface BandStyle {
  background: string;
}

function bandStylesForCard(card: CardLike): BandStyle[] {
  switch (card.category) {
    case 'item':
      return [{ background: colorHex(card.colors?.[0] ?? '') }];
    case 'wild_item_two_color':
      return [
        { background: colorHex(card.colors?.[0] ?? '') },
        { background: colorHex(card.colors?.[1] ?? '') },
      ];
    case 'wild_item_any_color':
      return [{ background: RAINBOW_GRADIENT }];
    case 'point':
      return [{ background: '#FCD34D' /* amber-300 */ }];
    case 'spell':
      return [{ background: '#E7E5E4' /* stone-200 */ }];
    case 'character':
      return [{ background: '#7F1D1D' /* maroon / red-900 */ }];
    default:
      return [{ background: '#9CA3AF' /* gray-400 */ }];
  }
}

/** Background tint for the card body (below the color band). */
function bodyClassesForCard(card: CardLike): string {
  switch (card.category) {
    case 'point':
      return 'bg-amber-200 text-amber-900';
    case 'spell':
      return 'bg-stone-100 text-stone-900';
    case 'character':
      return 'bg-red-50 text-red-950';
    default:
      return 'bg-white text-slate-900';
  }
}

export function Card(props: Props) {
  const { card, variant = 'full', faceDown = false, selected = false, onClick } = props;
  const c = card as unknown as CardLike;

  const interactive = typeof onClick === 'function';
  const sizeClasses = variantSize(variant);
  const ringClasses = selected ? 'ring-2 ring-emerald-500' : 'ring-1 ring-slate-200';
  const baseClasses =
    'relative rounded-md overflow-hidden shadow-sm select-none transition-shadow';
  const hoverClasses = interactive
    ? 'cursor-pointer hover:shadow-md active:shadow-inner min-w-[44px] min-h-[44px]'
    : '';

  const wrapperProps: React.HTMLAttributes<HTMLDivElement> & {
    role?: string;
    tabIndex?: number;
  } = {
    className: `${baseClasses} ${sizeClasses} ${ringClasses} ${hoverClasses}`,
  };
  if (interactive) {
    wrapperProps.onClick = onClick;
    wrapperProps.role = 'button';
    wrapperProps.tabIndex = 0;
    wrapperProps.onKeyDown = (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        onClick?.();
      }
    };
  }

  // ----- Face down -----
  if (faceDown) {
    return (
      <div
        {...wrapperProps}
        className={`${wrapperProps.className} bg-stone-800 flex items-center justify-center`}
        aria-label="Face-down card"
      >
        <span
          className={
            variant === 'thumbnail'
              ? 'text-amber-200 font-serif font-bold text-xl'
              : variant === 'compressed'
              ? 'text-amber-200 font-serif font-bold text-2xl'
              : 'text-amber-200 font-serif font-bold text-4xl'
          }
        >
          M
        </span>
      </div>
    );
  }

  const bands = bandStylesForCard(c);
  const bodyClasses = bodyClassesForCard(c);

  // ----- Thumbnail -----
  if (variant === 'thumbnail') {
    return (
      <div
        {...wrapperProps}
        className={`${wrapperProps.className} ${bodyClasses} flex flex-col`}
        aria-label={c.title}
        title={c.title}
      >
        <div className="flex h-3 w-full">
          {bands.map((b, i) => (
            <div key={i} className="flex-1" style={b} />
          ))}
        </div>
        <div className="flex-1 flex items-center justify-center">
          {c.cash_value != null && (
            <span className="text-[10px] font-bold leading-none">${c.cash_value}M</span>
          )}
        </div>
      </div>
    );
  }

  // ----- Compressed -----
  if (variant === 'compressed') {
    return (
      <div
        {...wrapperProps}
        className={`${wrapperProps.className} ${bodyClasses} flex flex-col`}
        aria-label={c.title}
        title={c.title}
      >
        <div className="flex h-2.5 w-full">
          {bands.map((b, i) => (
            <div key={i} className="flex-1" style={b} />
          ))}
        </div>
        <div className="flex-1 flex items-center justify-between px-2">
          <span className="text-xs font-semibold truncate">{c.title}</span>
          {c.cash_value != null && (
            <span className="ml-1 text-[10px] font-bold opacity-75 shrink-0">
              ${c.cash_value}M
            </span>
          )}
        </div>
      </div>
    );
  }

  // ----- Full -----
  const isPoint = c.category === 'point';
  const isCharacter = c.category === 'character';
  const isSpell = c.category === 'spell';

  return (
    <div
      {...wrapperProps}
      className={`${wrapperProps.className} ${bodyClasses} flex flex-col`}
      aria-label={c.title}
    >
      {/* Color band(s) */}
      <div className="flex h-5 w-full shrink-0">
        {bands.map((b, i) => (
          <div key={i} className="flex-1" style={b} />
        ))}
      </div>

      {/* Cash value badge (top-right) */}
      {c.cash_value != null && !isPoint && (
        <div className="absolute top-1.5 right-1.5 bg-white/90 text-slate-900 rounded-full px-1.5 py-0.5 text-[10px] font-bold shadow-sm">
          ${c.cash_value}M
        </div>
      )}

      {/* Body */}
      <div className="flex-1 flex flex-col px-2 py-1.5 min-h-0">
        {isPoint ? (
          <div className="flex-1 flex flex-col items-center justify-center">
            <span className="text-3xl font-extrabold leading-none">${c.cash_value}M</span>
            <span className="mt-1 text-[10px] uppercase tracking-wide opacity-70">
              {c.title}
            </span>
          </div>
        ) : isCharacter ? (
          <div className="flex-1 flex flex-col items-center justify-center text-center">
            <span className="text-base font-bold leading-tight">{c.title}</span>
            {c.rules_text && (
              <span className="mt-1 text-[10px] line-clamp-3 opacity-80">
                {c.rules_text}
              </span>
            )}
          </div>
        ) : isSpell ? (
          <>
            <div className="flex items-start justify-between gap-1">
              <span className="text-sm font-semibold leading-tight">{c.title}</span>
              <span className="text-lg leading-none" aria-hidden>
                {spellGlyph(c.spell_effect)}
              </span>
            </div>
            {c.rules_text && (
              <p className="mt-1 text-[10px] leading-snug line-clamp-3 opacity-80">
                {c.rules_text}
              </p>
            )}
          </>
        ) : (
          // item / wild
          <>
            <span className="text-sm font-semibold leading-tight">{c.title}</span>
            {c.rules_text && (
              <p className="mt-1 text-[10px] leading-snug line-clamp-3 opacity-70">
                {c.rules_text}
              </p>
            )}
          </>
        )}
      </div>
    </div>
  );
}

export default Card;
