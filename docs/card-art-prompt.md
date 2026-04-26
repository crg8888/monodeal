# Card Art Generation Prompt Package

For generating 111 consistent card face images via ChatGPT (or any image-gen model). The goal is **IP-adjacent magical academia aesthetic** — evocative of the Harry Potter universe without reproducing branded characters, logos, or actor likenesses. Image generators will usually refuse branded prompts, and IP-adjacent art produces better-looking and more visually consistent results.

---

## Style brief — read before generating any image

**Visual genre:** illustrated alchemical grimoire / magical academia. Think Victorian woodcut, hand-drawn parchment, tarot-card ornamentation. NOT photorealistic, NOT modern digital illustration, NOT the official Hasbro style, NOT movie stills.

**Palette (strict):**
- Primary: deep navy `#0a1628`, parchment `#f4e9d1`, muted gold `#c8a15b`
- Accent: oxblood `#6b1a1a`, emerald `#2d5a3d`, aged-rose `#a8516e`
- No saturated primaries. Everything reads like aged paper and candlelight.

**Line style:**
- Ink-etched outlines, medium weight
- Cross-hatch shading
- Gold filigree flourishes in corners

**Mood:** mysterious, scholarly, slightly whimsical. Sparse composition — ONE clear subject per card, centered on a parchment background.

**Absolute prohibitions (will cause refusals or bad output):**
- No branded names in the prompt: don't mention Harry Potter, Hogwarts, Gryffindor, Slytherin, Wizarding World, or any character actor
- No real people
- No text in the image (card frame + title will be overlaid by the app)
- No watermarks or signatures
- No photorealistic rendering
- No modern clothing or technology

**Technical requirements:**
- 2.5:3.5 portrait aspect ratio (approx 768×1075 px works well)
- Transparent or parchment-textured background
- Subject occupies the middle 60% of the image; leaves headroom for the title banner the app will overlay

---

## How to use this document

1. Pick a card from the list below.
2. Paste the **"base style block"** (below) + the card's **subject prompt** into ChatGPT image generation.
3. Download the image.
4. Upload via the admin page at `/admin?host_token=...`.
5. Repeat for each card.

For batch efficiency: you can chain 5-10 cards per ChatGPT conversation by saying "Use the exact same style as the previous image, now draw: [next subject prompt]."

---

## Base style block (prepend to every prompt)

```
Style: Alchemical grimoire illustration. Victorian ink etching with cross-hatch shading
and gold-filigree corner flourishes. Aged-parchment background (#f4e9d1). Deep navy,
muted gold, oxblood, emerald accents. Hand-drawn, slightly whimsical, tarot-adjacent.
No text, no branding, no real people, no modern elements. Centered subject occupying
middle 60% of frame. Portrait aspect 2.5:3.5.
```

---

## Card subjects — exact prompts per card

### Items (28 cards, grouped by color)

#### Brown — warm amber palette

**butterbeer** — *"A pewter tankard filled with frothing golden ale, steam curls upward in whimsical swirls. Sits on a wooden tavern shelf. Copper rivets and ornamented handle."*

**pumpkin_juice** — *"A tall glass bottle of orange-amber liquid, cork sealed with wax, small jack-o-lantern shape embossed on the glass. Stands among autumn leaves."*

#### Light-blue — pale ice palette

**berties_beans** — *"A small cardboard box spilling over with tiny multicolored jellybeans, each a slightly different jewel tone. Vintage candy shop aesthetic."*

**chocolate_frog** — *"A small, realistically detailed chocolate frog sitting on a open decorative pentagonal box. Steam rises faintly from the frog as if freshly cast."*

**cauldron_cake** — *"A small round cake shaped like a miniature cauldron, dark chocolate glaze dripping over the sides, sitting on a lace doily."*

#### Pink — rose palette

**brass_scales** — *"An antique balance scale with two brass pans, ornate central pillar with scrollwork, shown slightly tipped to one side."*

**dragon_hide_gloves** — *"A pair of thick gauntlet-style gloves made of scaled, dark-reddish hide, lying crossed on a workbench. Visible stitching and buckle details."*

**cauldron** — *"A cast-iron cauldron on three legs, dark liquid bubbling inside with faint pink steam curling up. Mounted on a stone hearth."*

#### Orange — deep ochre palette

**hogwarts_a_history** — *"An oversized leatherbound book with thick brass clasps, ornate gold-foil embossing on the cover, subtle castle silhouette etched into the leather. Book lies closed at an angle."*

**beginners_guide_to_transfiguration** — *"A slim cloth-bound textbook with a ribbon bookmark, chalk and quill resting beside it. Simple geometric-transformation diagram etched on the cover."*

**monster_book_of_monsters** — *"A fang-edged hardcover book bound in coarse fur, eyes and teeth visible around the edges, restraining strap across the cover. Ominously animated, not quite at rest."*

#### Light-green — mint/sage palette

**portkey** — *"An ordinary-looking old boot with a faint greenish aura shimmering around it, sitting on a mossy forest floor."*

**floo_powder** — *"A small cloth pouch spilling out shimmering green powder that sparkles like emerald dust. Next to a brass scoop."*

#### Black — deep charcoal palette

**toad** — *"A plump fantasy toad perched on a mossy stone, wide amber eyes, warty textured skin, one hind leg visible. Slight iridescent sheen."*

**rat** — *"A rotund, slightly scruffy rat sitting on its haunches on a tattered cushion. One ear bent, whiskers prominent."*

**owl** — *"A majestic horned owl perched on a tarnished silver perch, head turned in profile, feathers detailed with cross-hatch."*

**cat** — *"An elegant cat with slightly flattened face and long fur, sitting regally on a velvet cushion. Wise amber eyes."*

#### Red — deep crimson palette

**quaffle** — *"A sport ball made of red leather with white stitched panels, small grip indents on the surface. Floats mid-air as if charmed."*

**bludger** — *"A heavy black iron sphere, slightly battered, floating menacingly with faint motion blur suggesting it's about to lunge. Rivets and wear marks visible."*

**snitch** — *"A small golden ball with two delicate silver wings extended mid-flight. Intricate filigree covering the sphere. Shown against a blurred dark background to emphasize the gleam."*

#### Yellow — warm gold palette

**omnioculars** — *"Brass opera-glasses with ornate engraving, leather strap, tiny dials and lenses at various magnifications. Sit on a velvet display pillow."*

**remembrall** — *"A small clear glass sphere on a tiny silver stand, white smoke swirling inside, sitting on a cluttered desk with quills and parchment."*

**sneakoscope** — *"An ornate spinning-top shaped metal device with multiple rotating rings and etched runes, glowing faintly from within. On a wooden map-table."*

#### Dark-blue — deep indigo palette

**felix_felicis** — *"A small crystal vial containing molten-gold liquid that seems to shimmer and flow upward against gravity. Wax-sealed stopper, faceted bottle, on a velvet display."*

**veritaserum** — *"A clear apothecary bottle with a long dropper, filled with water-clear liquid that has faint blue sparkles. Stoppered with cork."*

#### Dark-green — forest palette

**amortentia** — *"A pearlescent-surfaced potion in a round glass flask, gentle iridescent swirls rising as steam forms heart-shapes. On a lace-covered apothecary counter."*

**aging_potion** — *"A brass-filigreed bottle of amber liquid, the glass slightly frosted, sitting next to an hourglass spilling golden sand."*

**polyjuice_potion** — *"A dense, sludgy green potion bubbling in a cauldron-shaped flask, thick consistency obvious from the viscous ripples. Cork stopper tied with twine."*

---

### Wild items (11 cards)

#### Two-color wild (9 cards, one per pairing)

**wild_brown_light_blue** — *"Two overlapping jars — one amber, one pale blue — sitting side by side on a shelf. Rich and glowing, connected by a shared ribbon."*

**wild_pink_orange** — *"A balance scale with a small rose-pink book on one pan and a glowing orange gem on the other, tipped to balance."*

**wild_pink_yellow** — *"A magnifying glass and a pair of rose-pink gloves crossed on a parchment scroll. Subjects share a golden glow."*

**wild_red_yellow** — *"A small golden ball with faint wings resting on a deep-red leather journal. Single brass-orange ember floats above them."*

**wild_red_yellow_alt** — *(same as above, alternate composition)* *"A crimson quaffle-ball and a brass-orange-rimmed compass crossed over an old parchment. Warm glow."*

**wild_light_blue_black** — *"A pale-blue crystal orb resting on a dark feathered wing. Cool-toned illustration with deep shadow underneath."*

**wild_light_blue_brown** — *"A clear vial of amber liquid and a small pale-blue pebble sitting on a handwritten recipe card."*

**wild_dark_green_black** — *"A deep-green sprig of mandrake leaves wrapped around a dark iron key. Bound with a velvet ribbon."*

**wild_dark_green_dark_blue** — *"A small deep-emerald potion bottle next to a midnight-blue astrolabe. Ornate brass details shared between them."*

#### Every-color wild (2 cards, identical subject)

**wild_any_color** — *"A prismatic phoenix with iridescent plumage shifting through every color of the rainbow, wings half-spread, rising from a small pile of gold-flecked ashes. Sparks and motes of color drifting around it. Majestic."*

---

### Characters (5 cards — no real-person likenesses)

Describe characters archetypally without naming actors or using book/film descriptions as reference. The point is to evoke the vibe without triggering refusals.

**harry** — *"A young wizard student with messy dark hair and round glasses, wearing school robes with a crimson-and-gold striped scarf. Holds a wand at his side. Determined expression. Shown from chest up. Subtle lightning detail above the brow but stylized, not literal."*

**draco** — *"A young wizard student with pale blond slicked-back hair, sharp features, wearing school robes with an emerald-and-silver striped scarf. Smug half-smile. Arms crossed. Shown from chest up."*

**hermione** — *"A young witch student with voluminous curly brown hair, wearing school robes with a crimson-and-gold striped scarf. Holds an open textbook in one hand, wand in the other. Focused expression. Shown from chest up."*

**luna** — *"A young witch student with long wavy pale-blonde hair, dreamy expression, wearing school robes with a deep-blue-and-bronze striped scarf. Large unusual earrings. Holding a butterbeer-cork necklace. Shown from chest up."*

**cedric** — *"A young wizard student with short tousled light-brown hair, friendly confident expression, wearing school robes with a yellow-and-black striped scarf. Holds a wand casually. Athletic build. Shown from chest up."*

---

### Spell cards (12 unique effects)

All spells share a common visual language: a magical effect emanating from a wand or in mid-cast, against a dark starfield background with gold filigree borders.

**accio** (10 + 3 copies use same art) — *"A wand pointed forward with curved golden lines flowing toward it from off-frame, as if summoning an unseen object. Magical glow, wisps of light converging. Dark navy background with gold stars."*

**alohomora** — *"A wand pointed at an antique brass keyhole with a glowing gold lock mechanism rotating in mid-air. Gold-filigree border. Dark starfield."*

**confundo** — *"Two wispy silhouettes of objects crossing in mid-swap above a wand, motion trails suggesting they're being exchanged. Spiral of gold dust."*

**geminio** — *"A single wand casting, with a second identical wand-image appearing as if duplicated beside it. Subtle ghost-overlay effect."*

**levicorpus** — *"A wand pointing upward with an object silhouette floating mid-air above it, cords of golden light wrapping around the object."*

**obliviate** — *"A wand releasing a billowing cloud of silvery-gold smoke that seems to be erasing marks on a scroll. Dissolving memory motif."*

**petrificus_totalus** — *"A wand pointing forward with sharp angular golden ice/crystal formations freezing in mid-air ahead of it. Rigid lines, stark contrast."*

**protego** — *"A glowing translucent shield of interlocking gold-filigree patterns materializing in front of a wand, as if deflecting something. Shield emblem central."*

**reparo** — *"A wand pointing at fragments of an object (pieces of pottery or parchment) that are floating together mid-repair, gold light knitting them at the seams."*

**stupefy** — *"A wand releasing a bright forked bolt of red-gold lightning straight forward. Dramatic lighting contrast."*

**wingardium_leviosa** — *"A wand raised upward with a feather floating gracefully mid-air above it, delicate motion-trail of gold dust spiraling up."*

---

### Point cards (6 unique denominations)

Point cards have a simpler ornamental style — large numerical value dominates the composition.

**point_1** — *"An ornate gold coin embossed with a stylized ''1' and filigree edging, against a soft parchment background. Tarnish and wear suggest it's well-used."*

**point_2** — *"Two overlapping gold coins embossed with ''2', artfully arranged with shadow underneath."*

**point_3** — *"A small stack of three tarnished gold coins, rim filigree visible on the top one, numeric ''3' subtly embossed."*

**point_4** — *"Four gold coins arranged in a diamond, each with faint filigree, unified by ornamental '4' in the center."*

**point_5** — *"A decorative pouch half-open, spilling five gold coins onto a velvet surface. Central large ''5' embossed."*

**point_10** — *"A heavy ornate chest overflowing with gold coins, lid thrown open. Central large ''10' elegantly rendered above the treasure."*

---

## Batch generation workflow (recommended)

Paste this into ChatGPT at the start of a new conversation:

```
I'm going to ask you to generate a series of card-face images for a card game in a
consistent style. Apply this style block to every image, and whenever I say "next,"
maintain the exact same visual treatment:

[PASTE BASE STYLE BLOCK HERE]

Do not add any text or titles to the images; the card frames will overlay text later.
Do not include branded names, real people, or movie references. Keep the aesthetic
consistent: alchemical grimoire, ink-etching, parchment, gold filigree.

First image: [PASTE FIRST SUBJECT PROMPT HERE]
```

Then for each next card:

```
Next, same style: [NEXT SUBJECT PROMPT]
```

When you see drift, reset the conversation with a fresh paste of the base style block.

---

## Quality checklist per image before uploading

- [ ] Composition is centered with headroom at top for title overlay
- [ ] No text in the image
- [ ] Palette stays within the brief (deep navy, parchment, muted gold, oxblood, emerald)
- [ ] Subject is unambiguous — would a player recognize what this is?
- [ ] Style matches previous images (ink-etching, cross-hatch shading, filigree corners)
- [ ] No branded elements or real people
- [ ] Aspect ratio approximately 2.5:3.5

If any fails, regenerate before uploading.

---

## Upload process

1. Open `/admin?host_token=...` (token from your localStorage after first join).
2. Find the card by slug in the card list.
3. Click the image-upload button next to it.
4. Pick the file → uploads to Supabase Storage `card_art/` bucket.
5. URL auto-saves to `cards.art_asset_url`.
6. All connected players see the new art within ~2 seconds via realtime.

No redeploy needed. If you want to replace an image, upload again — it overwrites.
