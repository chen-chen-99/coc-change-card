-- =====================================================================
-- 迁移脚本 v2：卡牌种类（category）+ 60 张真实卡牌
-- ---------------------------------------------------------------------
-- 适用：已执行过旧版 schema.sql（12 张 c01~c12）的数据库。
-- 执行后：cards 增加 category 列；删除该活动旧种子卡及其库存；
--         插入 60 张真实卡牌（e01~e19 / d01~d13 / b01~b11 / s01~s17）；
--         为已有玩家补齐新卡库存行（数量 0）。
-- =====================================================================

-- 1) 增加种类列
alter table public.cards add column if not exists category text;

-- 2) 移除旧的“同活动内卡名唯一”约束（不同种类存在同名兵种，如 飞龙宝宝）
alter table public.cards drop constraint if exists cards_activity_id_name_key;

-- 3) 删除该活动旧种子卡及其库存（保留其他活动数据）
delete from public.player_cards pc
using public.cards c
where pc.card_id = c.card_id and c.activity_id = 'card_clash_2026_08';
delete from public.cards where activity_id = 'card_clash_2026_08';

-- 4) 重新插入 60 张真实卡牌
insert into public.cards (card_id, activity_id, name, category, image_url, sort_order) values
('e01', 'card_clash_2026_08', '野蛮人', 'elixir', 'images/cards/e01.png', 1),
('e02', 'card_clash_2026_08', '弓箭手', 'elixir', 'images/cards/e02.png', 2),
('e03', 'card_clash_2026_08', '巨人', 'elixir', 'images/cards/e03.png', 3),
('e04', 'card_clash_2026_08', '哥布林', 'elixir', 'images/cards/e04.png', 4),
('e05', 'card_clash_2026_08', '炸弹人', 'elixir', 'images/cards/e05.png', 5),
('e06', 'card_clash_2026_08', '气球兵', 'elixir', 'images/cards/e06.png', 6),
('e07', 'card_clash_2026_08', '法师', 'elixir', 'images/cards/e07.png', 7),
('e08', 'card_clash_2026_08', '天使', 'elixir', 'images/cards/e08.png', 8),
('e09', 'card_clash_2026_08', '飞龙', 'elixir', 'images/cards/e09.png', 9),
('e10', 'card_clash_2026_08', '皮卡超人', 'elixir', 'images/cards/e10.png', 10),
('e11', 'card_clash_2026_08', '飞龙宝宝', 'elixir', 'images/cards/e11.png', 11),
('e12', 'card_clash_2026_08', '掘地矿工', 'elixir', 'images/cards/e12.png', 12),
('e13', 'card_clash_2026_08', '雷电飞龙', 'elixir', 'images/cards/e13.png', 13),
('e14', 'card_clash_2026_08', '大雪怪', 'elixir', 'images/cards/e14.png', 14),
('e15', 'card_clash_2026_08', '龙骑士', 'elixir', 'images/cards/e15.png', 15),
('e16', 'card_clash_2026_08', '雷霆泰坦', 'elixir', 'images/cards/e16.png', 16),
('e17', 'card_clash_2026_08', '根蔓骑士', 'elixir', 'images/cards/e17.png', 17),
('e18', 'card_clash_2026_08', '巨矛投手', 'elixir', 'images/cards/e18.png', 18),
('e19', 'card_clash_2026_08', '陨石戈仑', 'elixir', 'images/cards/e19.png', 19),
('d01', 'card_clash_2026_08', '亡灵', 'dark_elixir', 'images/cards/d01.png', 20),
('d02', 'card_clash_2026_08', '野猪骑士', 'dark_elixir', 'images/cards/d02.png', 21),
('d03', 'card_clash_2026_08', '瓦基里丽武神', 'dark_elixir', 'images/cards/d03.png', 22),
('d04', 'card_clash_2026_08', '戈仑石人', 'dark_elixir', 'images/cards/d04.png', 23),
('d05', 'card_clash_2026_08', '女巫', 'dark_elixir', 'images/cards/d05.png', 24),
('d06', 'card_clash_2026_08', '熔岩猎犬', 'dark_elixir', 'images/cards/d06.png', 25),
('d07', 'card_clash_2026_08', '巨石投手', 'dark_elixir', 'images/cards/d07.png', 26),
('d08', 'card_clash_2026_08', '戈仑冰人', 'dark_elixir', 'images/cards/d08.png', 27),
('d09', 'card_clash_2026_08', '英雄猎手', 'dark_elixir', 'images/cards/d09.png', 28),
('d10', 'card_clash_2026_08', '守护者学徒', 'dark_elixir', 'images/cards/d10.png', 29),
('d11', 'card_clash_2026_08', '德鲁伊', 'dark_elixir', 'images/cards/d11.png', 30),
('d12', 'card_clash_2026_08', '烈焰熔炉', 'dark_elixir', 'images/cards/d12.png', 31),
('d13', 'card_clash_2026_08', '废墟女巫', 'dark_elixir', 'images/cards/d13.png', 32),
('b01', 'card_clash_2026_08', '狂暴野蛮人', 'builder_base', 'images/cards/b01.png', 33),
('b02', 'card_clash_2026_08', '隐秘弓箭手', 'builder_base', 'images/cards/b02.png', 34),
('b03', 'card_clash_2026_08', '巨人拳击手', 'builder_base', 'images/cards/b03.png', 35),
('b04', 'card_clash_2026_08', '异变亡灵', 'builder_base', 'images/cards/b04.png', 36),
('b05', 'card_clash_2026_08', '炸弹兵', 'builder_base', 'images/cards/b05.png', 37),
('b06', 'card_clash_2026_08', '飞龙宝宝', 'builder_base', 'images/cards/b06.png', 38),
('b07', 'card_clash_2026_08', '加农炮战车', 'builder_base', 'images/cards/b07.png', 39),
('b08', 'card_clash_2026_08', '暗夜女巫', 'builder_base', 'images/cards/b08.png', 40),
('b09', 'card_clash_2026_08', '骷髅气球', 'builder_base', 'images/cards/b09.png', 41),
('b10', 'card_clash_2026_08', '雷霆皮卡', 'builder_base', 'images/cards/b10.png', 42),
('b11', 'card_clash_2026_08', '野猪飞骑', 'builder_base', 'images/cards/b11.png', 43),
('s01', 'card_clash_2026_08', '超级野蛮人', 'super_troop', 'images/cards/s01.png', 44),
('s02', 'card_clash_2026_08', '超级弓箭手', 'super_troop', 'images/cards/s02.png', 45),
('s03', 'card_clash_2026_08', '超级巨人', 'super_troop', 'images/cards/s03.png', 46),
('s04', 'card_clash_2026_08', '隐秘哥布林', 'super_troop', 'images/cards/s04.png', 47),
('s05', 'card_clash_2026_08', '超级炸弹人', 'super_troop', 'images/cards/s05.png', 48),
('s06', 'card_clash_2026_08', '火箭气球兵', 'super_troop', 'images/cards/s06.png', 49),
('s07', 'card_clash_2026_08', '超级法师', 'super_troop', 'images/cards/s07.png', 50),
('s08', 'card_clash_2026_08', '超级飞龙', 'super_troop', 'images/cards/s08.png', 51),
('s09', 'card_clash_2026_08', '地狱飞龙', 'super_troop', 'images/cards/s09.png', 52),
('s10', 'card_clash_2026_08', '超级矿工', 'super_troop', 'images/cards/s10.png', 53),
('s11', 'card_clash_2026_08', '超级大雪怪', 'super_troop', 'images/cards/s11.png', 54),
('s12', 'card_clash_2026_08', '超级亡灵', 'super_troop', 'images/cards/s12.png', 55),
('s13', 'card_clash_2026_08', '超级野猪骑士', 'super_troop', 'images/cards/s13.png', 56),
('s14', 'card_clash_2026_08', '超级瓦基丽武神', 'super_troop', 'images/cards/s14.png', 57),
('s15', 'card_clash_2026_08', '超级女巫', 'super_troop', 'images/cards/s15.png', 58),
('s16', 'card_clash_2026_08', '寒冰猎犬', 'super_troop', 'images/cards/s16.png', 59),
('s17', 'card_clash_2026_08', '超级巨石投手', 'super_troop', 'images/cards/s17.png', 60)
on conflict (card_id) do nothing;

-- 5) 已有玩家：为新卡牌补充库存行（数量 0）
insert into public.player_cards (player_id, card_id, quantity)
select p.player_id, c.card_id, 0
from public.players p
cross join public.cards c
where c.activity_id = 'card_clash_2026_08'
  and not exists (
    select 1 from public.player_cards pc
    where pc.player_id = p.player_id and pc.card_id = c.card_id
  );