-- Slice 0: seed the 111-card deck + item_sets reference table.
-- Source: docs/lovable-prompt-v5.md, "Deck composition" + "Item sets" sections.
-- Hard-fails the migration if counts/categories don't match the authoritative deck.

-- ============================================================================
-- Item sets (10 colors)
-- ============================================================================

insert into item_sets (color, set_size, cash_value, charge_table) values
  ('brown',       2, 1, '{"1": 1, "complete": 2}'::jsonb),
  ('light-blue',  3, 1, '{"1": 1, "2": 2, "complete": 3}'::jsonb),
  ('pink',        3, 2, '{"1": 1, "2": 2, "complete": 4}'::jsonb),
  ('orange',      3, 2, '{"1": 1, "2": 3, "complete": 5}'::jsonb),
  ('light-green', 2, 2, '{"1": 1, "complete": 2}'::jsonb),
  ('black',       4, 2, '{"1": 1, "2": 2, "3": 3, "complete": 4}'::jsonb),
  ('red',         3, 3, '{"1": 2, "2": 3, "complete": 6}'::jsonb),
  ('yellow',      3, 3, '{"1": 2, "2": 4, "complete": 6}'::jsonb),
  ('dark-blue',   2, 4, '{"1": 3, "complete": 8}'::jsonb),
  ('dark-green',  3, 4, '{"1": 2, "2": 4, "complete": 7}'::jsonb);

-- ============================================================================
-- Characters (5)
-- ============================================================================

insert into cards (slug, category, title, flavor_text, rules_text) values
  ('character_harry',    'character', 'Harry Potter',
   'When hiding under his invisibility cloak, no one will see what you''re carrying!',
   'At character select, pick one color. While not petrified, your items of that color cannot be taken or discarded by opponents'' spells.'),
  ('character_draco',    'character', 'Draco Malfoy',
   'Mention his father''s name and you can get away with anything.',
   'While not petrified, you may take items that are part of a complete set via Confundo, Levicorpus, Wingardium Leviosa.'),
  ('character_hermione', 'character', 'Hermione Granger',
   'You never know what useful spell she might discover in the library.',
   'While not petrified, plays_allowed_this_turn = 4 instead of 3.'),
  ('character_luna',     'character', 'Luna Lovegood',
   'When you open your mind to the unexpected, extraordinary opportunities may present themselves!',
   'While not petrified, at start of turn draw 3 cards instead of 2 (unless hand is empty; then still 5).'),
  ('character_cedric',   'character', 'Cedric Diggory',
   'With the dedication and resourcefulness of a true Hufflepuff, he finds value where others don''t.',
   'While not petrified, at start of turn may draw from discard instead of deck.');

-- ============================================================================
-- Magical items (28)
-- ============================================================================

insert into cards (slug, category, title, cash_value, colors) values
  -- brown (2)
  ('item_butterbeer',      'item', 'Butterbeer',     1, '{brown}'),
  ('item_pumpkin_juice',   'item', 'Pumpkin Juice',  1, '{brown}'),
  -- light-blue (3)
  ('item_berties_beans',   'item', 'Bertie''s Every-Flavour Beans', 1, '{light-blue}'),
  ('item_chocolate_frog',  'item', 'Chocolate Frog', 1, '{light-blue}'),
  ('item_cauldron_cake',   'item', 'Cauldron Cake',  1, '{light-blue}'),
  -- pink (3)
  ('item_brass_scales',       'item', 'Brass Scales',       2, '{pink}'),
  ('item_dragon_hide_gloves', 'item', 'Dragon Hide Gloves', 2, '{pink}'),
  ('item_cauldron',           'item', 'Cauldron',           2, '{pink}'),
  -- orange (3)
  ('item_hogwarts_a_history',                   'item', 'Hogwarts: A History',                   2, '{orange}'),
  ('item_beginners_guide_to_transfiguration',   'item', 'Beginner''s Guide to Transfiguration',  2, '{orange}'),
  ('item_monster_book_of_monsters',             'item', 'The Monster Book of Monsters',          2, '{orange}'),
  -- light-green (2)
  ('item_portkey',     'item', 'Portkey',     2, '{light-green}'),
  ('item_floo_powder', 'item', 'Floo Powder', 2, '{light-green}'),
  -- black (4)
  ('item_toad', 'item', 'Toad', 2, '{black}'),
  ('item_rat',  'item', 'Rat',  2, '{black}'),
  ('item_owl',  'item', 'Owl',  2, '{black}'),
  ('item_cat',  'item', 'Cat',  2, '{black}'),
  -- red (3)
  ('item_quaffle', 'item', 'Quaffle', 3, '{red}'),
  ('item_bludger', 'item', 'Bludger', 3, '{red}'),
  ('item_snitch',  'item', 'Snitch',  3, '{red}'),
  -- yellow (3)
  ('item_omnioculars',  'item', 'Omnioculars',  3, '{yellow}'),
  ('item_remembrall',   'item', 'Remembrall',   3, '{yellow}'),
  ('item_sneakoscope',  'item', 'Sneakoscope',  3, '{yellow}'),
  -- dark-blue (2)
  ('item_felix_felicis', 'item', 'Felix Felicis', 4, '{dark-blue}'),
  ('item_veritaserum',   'item', 'Veritaserum',   4, '{dark-blue}'),
  -- dark-green (3)
  ('item_amortentia',      'item', 'Amortentia',      4, '{dark-green}'),
  ('item_aging_potion',    'item', 'Aging Potion',    4, '{dark-green}'),
  ('item_polyjuice_potion','item', 'Polyjuice Potion', 4, '{dark-green}');

-- ============================================================================
-- Two-color wild items (9). Cash value & color pairings per spec table.
-- wild_charge_tables holds each color's charge_table keyed by color slug.
-- ============================================================================

insert into cards (slug, category, title, cash_value, colors, wild_charge_tables) values
  ('wild_two_brown_lightblue',       'wild_item_two_color', 'Wild Item: Brown / Light Blue',    1, '{brown,light-blue}',
   '{"brown": {"1": 1, "complete": 2}, "light-blue": {"1": 1, "2": 2, "complete": 3}}'::jsonb),
  ('wild_two_pink_orange',           'wild_item_two_color', 'Wild Item: Pink / Orange',         2, '{pink,orange}',
   '{"pink": {"1": 1, "2": 2, "complete": 4}, "orange": {"1": 1, "2": 3, "complete": 5}}'::jsonb),
  ('wild_two_pink_yellow',           'wild_item_two_color', 'Wild Item: Pink / Yellow',         2, '{pink,yellow}',
   '{"pink": {"1": 1, "2": 2, "complete": 4}, "yellow": {"1": 2, "2": 4, "complete": 6}}'::jsonb),
  ('wild_two_red_yellow_a',          'wild_item_two_color', 'Wild Item: Red / Yellow',          3, '{red,yellow}',
   '{"red": {"1": 2, "2": 3, "complete": 6}, "yellow": {"1": 2, "2": 4, "complete": 6}}'::jsonb),
  ('wild_two_red_yellow_b',          'wild_item_two_color', 'Wild Item: Red / Yellow',          3, '{red,yellow}',
   '{"red": {"1": 2, "2": 3, "complete": 6}, "yellow": {"1": 2, "2": 4, "complete": 6}}'::jsonb),
  ('wild_two_lightblue_black',       'wild_item_two_color', 'Wild Item: Light Blue / Black',    2, '{light-blue,black}',
   '{"light-blue": {"1": 1, "2": 2, "complete": 3}, "black": {"1": 1, "2": 2, "3": 3, "complete": 4}}'::jsonb),
  ('wild_two_lightblue_brown',       'wild_item_two_color', 'Wild Item: Light Blue / Brown',    1, '{light-blue,brown}',
   '{"light-blue": {"1": 1, "2": 2, "complete": 3}, "brown": {"1": 1, "complete": 2}}'::jsonb),
  ('wild_two_darkgreen_black',       'wild_item_two_color', 'Wild Item: Dark Green / Black',    4, '{dark-green,black}',
   '{"dark-green": {"1": 2, "2": 4, "complete": 7}, "black": {"1": 1, "2": 2, "3": 3, "complete": 4}}'::jsonb),
  ('wild_two_darkgreen_darkblue',    'wild_item_two_color', 'Wild Item: Dark Green / Dark Blue', 4, '{dark-green,dark-blue}',
   '{"dark-green": {"1": 2, "2": 4, "complete": 7}, "dark-blue": {"1": 3, "complete": 8}}'::jsonb);

-- ============================================================================
-- Every-color wilds (2). Cash 0; cannot bank or pay with; cannot solo-form a set.
-- ============================================================================

insert into cards (slug, category, title, cash_value, colors) values
  ('wild_any_color_a', 'wild_item_any_color', 'Wild Item: Every Color', 0,
   '{brown,light-blue,pink,orange,light-green,black,red,yellow,dark-blue,dark-green}'),
  ('wild_any_color_b', 'wild_item_any_color', 'Wild Item: Every Color', 0,
   '{brown,light-blue,pink,orange,light-green,black,red,yellow,dark-blue,dark-green}');

-- ============================================================================
-- Point cards (20)
-- 1×6, 2×5, 3×3, 4×3, 5×2, 10×1
-- ============================================================================

insert into cards (slug, category, title, cash_value) values
  ('point_1_a', 'point', 'Point Card (1)', 1),
  ('point_1_b', 'point', 'Point Card (1)', 1),
  ('point_1_c', 'point', 'Point Card (1)', 1),
  ('point_1_d', 'point', 'Point Card (1)', 1),
  ('point_1_e', 'point', 'Point Card (1)', 1),
  ('point_1_f', 'point', 'Point Card (1)', 1),
  ('point_2_a', 'point', 'Point Card (2)', 2),
  ('point_2_b', 'point', 'Point Card (2)', 2),
  ('point_2_c', 'point', 'Point Card (2)', 2),
  ('point_2_d', 'point', 'Point Card (2)', 2),
  ('point_2_e', 'point', 'Point Card (2)', 2),
  ('point_3_a', 'point', 'Point Card (3)', 3),
  ('point_3_b', 'point', 'Point Card (3)', 3),
  ('point_3_c', 'point', 'Point Card (3)', 3),
  ('point_4_a', 'point', 'Point Card (4)', 4),
  ('point_4_b', 'point', 'Point Card (4)', 4),
  ('point_4_c', 'point', 'Point Card (4)', 4),
  ('point_5_a', 'point', 'Point Card (5)', 5),
  ('point_5_b', 'point', 'Point Card (5)', 5),
  ('point_10_a', 'point', 'Point Card (10)', 10);

-- ============================================================================
-- Spells (47 total)
-- ============================================================================

-- Accio (paired): 2 each of 5 pairings = 10
insert into cards (slug, category, title, cash_value, spell_effect, spell_allowed_colors) values
  ('accio_brown_light_blue_a',    'spell', 'Accio (Brown / Light Blue)',     1, 'accio_brown_light_blue',    '{brown,light-blue}'),
  ('accio_brown_light_blue_b',    'spell', 'Accio (Brown / Light Blue)',     1, 'accio_brown_light_blue',    '{brown,light-blue}'),
  ('accio_pink_orange_a',         'spell', 'Accio (Pink / Orange)',          1, 'accio_pink_orange',         '{pink,orange}'),
  ('accio_pink_orange_b',         'spell', 'Accio (Pink / Orange)',          1, 'accio_pink_orange',         '{pink,orange}'),
  ('accio_light_green_black_a',   'spell', 'Accio (Light Green / Black)',    1, 'accio_light_green_black',   '{light-green,black}'),
  ('accio_light_green_black_b',   'spell', 'Accio (Light Green / Black)',    1, 'accio_light_green_black',   '{light-green,black}'),
  ('accio_red_yellow_a',          'spell', 'Accio (Red / Yellow)',           1, 'accio_red_yellow',          '{red,yellow}'),
  ('accio_red_yellow_b',          'spell', 'Accio (Red / Yellow)',           1, 'accio_red_yellow',          '{red,yellow}'),
  ('accio_dark_blue_dark_green_a','spell', 'Accio (Dark Blue / Dark Green)', 1, 'accio_dark_blue_dark_green','{dark-blue,dark-green}'),
  ('accio_dark_blue_dark_green_b','spell', 'Accio (Dark Blue / Dark Green)', 1, 'accio_dark_blue_dark_green','{dark-blue,dark-green}');

-- Accio (any): 3
insert into cards (slug, category, title, cash_value, spell_effect, spell_allowed_colors) values
  ('accio_any_a', 'spell', 'Accio (Any Color)', 3, 'accio_any',
   '{brown,light-blue,pink,orange,light-green,black,red,yellow,dark-blue,dark-green}'),
  ('accio_any_b', 'spell', 'Accio (Any Color)', 3, 'accio_any',
   '{brown,light-blue,pink,orange,light-green,black,red,yellow,dark-blue,dark-green}'),
  ('accio_any_c', 'spell', 'Accio (Any Color)', 3, 'accio_any',
   '{brown,light-blue,pink,orange,light-green,black,red,yellow,dark-blue,dark-green}');

-- Geminio (10) — draw 2
insert into cards (slug, category, title, cash_value, spell_effect) values
  ('geminio_01', 'spell', 'Geminio', 1, 'geminio'),
  ('geminio_02', 'spell', 'Geminio', 1, 'geminio'),
  ('geminio_03', 'spell', 'Geminio', 1, 'geminio'),
  ('geminio_04', 'spell', 'Geminio', 1, 'geminio'),
  ('geminio_05', 'spell', 'Geminio', 1, 'geminio'),
  ('geminio_06', 'spell', 'Geminio', 1, 'geminio'),
  ('geminio_07', 'spell', 'Geminio', 1, 'geminio'),
  ('geminio_08', 'spell', 'Geminio', 1, 'geminio'),
  ('geminio_09', 'spell', 'Geminio', 1, 'geminio'),
  ('geminio_10', 'spell', 'Geminio', 1, 'geminio');

-- Reparo (2) — take from discard
insert into cards (slug, category, title, cash_value, spell_effect) values
  ('reparo_a', 'spell', 'Reparo', 2, 'reparo'),
  ('reparo_b', 'spell', 'Reparo', 2, 'reparo');

-- Alohomora (3) — each opponent pays 2
insert into cards (slug, category, title, cash_value, spell_effect) values
  ('alohomora_a', 'spell', 'Alohomora', 2, 'alohomora'),
  ('alohomora_b', 'spell', 'Alohomora', 2, 'alohomora'),
  ('alohomora_c', 'spell', 'Alohomora', 2, 'alohomora');

-- Confundo (3) — swap one item
insert into cards (slug, category, title, cash_value, spell_effect) values
  ('confundo_a', 'spell', 'Confundo', 3, 'confundo'),
  ('confundo_b', 'spell', 'Confundo', 3, 'confundo'),
  ('confundo_c', 'spell', 'Confundo', 3, 'confundo');

-- Stupefy (3) — one opponent pays 5
insert into cards (slug, category, title, cash_value, spell_effect) values
  ('stupefy_a', 'spell', 'Stupefy', 3, 'stupefy'),
  ('stupefy_b', 'spell', 'Stupefy', 3, 'stupefy'),
  ('stupefy_c', 'spell', 'Stupefy', 3, 'stupefy');

-- Levicorpus (3) — take one item
insert into cards (slug, category, title, cash_value, spell_effect) values
  ('levicorpus_a', 'spell', 'Levicorpus', 3, 'levicorpus'),
  ('levicorpus_b', 'spell', 'Levicorpus', 3, 'levicorpus'),
  ('levicorpus_c', 'spell', 'Levicorpus', 3, 'levicorpus');

-- Protego (3) — reaction
insert into cards (slug, category, title, cash_value, spell_effect) values
  ('protego_a', 'spell', 'Protego', 4, 'protego'),
  ('protego_b', 'spell', 'Protego', 4, 'protego'),
  ('protego_c', 'spell', 'Protego', 4, 'protego');

-- Wingardium Leviosa (3) — discard one item
insert into cards (slug, category, title, cash_value, spell_effect) values
  ('wingardium_leviosa_a', 'spell', 'Wingardium Leviosa', 4, 'wingardium_leviosa'),
  ('wingardium_leviosa_b', 'spell', 'Wingardium Leviosa', 4, 'wingardium_leviosa'),
  ('wingardium_leviosa_c', 'spell', 'Wingardium Leviosa', 4, 'wingardium_leviosa');

-- Petrificus Totalus (2) — attaches to opponent
insert into cards (slug, category, title, cash_value, spell_effect) values
  ('petrificus_totalus_a', 'spell', 'Petrificus Totalus', 5, 'petrificus_totalus'),
  ('petrificus_totalus_b', 'spell', 'Petrificus Totalus', 5, 'petrificus_totalus');

-- Obliviate (2) — take complete set
insert into cards (slug, category, title, cash_value, spell_effect) values
  ('obliviate_a', 'spell', 'Obliviate', 5, 'obliviate'),
  ('obliviate_b', 'spell', 'Obliviate', 5, 'obliviate');

-- ============================================================================
-- Hard-fail assertions: deck must be exactly 111 cards in the documented split.
-- Source: docs/lovable-prompt-v5.md lines ~234-256.
-- ============================================================================

do $$ begin
  assert (select count(*) from cards) = 111, 'deck total must be 111';
  assert (select count(*) from cards where category != 'character') = 106;
  assert (select count(*) from cards where category = 'character') = 5;
  assert (select count(*) from cards where category = 'item') = 28;
  assert (select count(*) from cards where category = 'wild_item_two_color') = 9;
  assert (select count(*) from cards where category = 'wild_item_any_color') = 2;
  assert (select count(*) from cards where category = 'point') = 20;
  assert (select count(*) from cards where spell_effect like 'accio_%' and spell_effect != 'accio_any') = 10;
  assert (select count(*) from cards where spell_effect = 'accio_any') = 3;
  assert (select count(*) from cards where spell_effect = 'geminio') = 10;
  assert (select count(*) from cards where spell_effect = 'reparo') = 2;
  assert (select count(*) from cards where spell_effect = 'alohomora') = 3;
  assert (select count(*) from cards where spell_effect = 'confundo') = 3;
  assert (select count(*) from cards where spell_effect = 'stupefy') = 3;
  assert (select count(*) from cards where spell_effect = 'levicorpus') = 3;
  assert (select count(*) from cards where spell_effect = 'protego') = 3;
  assert (select count(*) from cards where spell_effect = 'wingardium_leviosa') = 3;
  assert (select count(*) from cards where spell_effect = 'petrificus_totalus') = 2;
  assert (select count(*) from cards where spell_effect = 'obliviate') = 2;
end $$;
