-- =====================================================================
-- 《部落冲突》卡牌冲突活动 —— Supabase 初始化脚本（v2：卡牌种类）
-- ---------------------------------------------------------------------
-- 使用方法：在 Supabase Dashboard → SQL Editor 中整体执行一次即可。
-- 包含：表结构、RLS 策略、匿名登录 RPC、真实卡牌种子数据（60 张）。
--
-- 注意：若你已执行过旧版（12 张 c01~c12）且库中已有数据，
--       请改用 migration_v2_cards.sql；首次搭建直接用本文件。
-- =====================================================================

create extension if not exists "pgcrypto";

-- =====================================================================
-- 1. 活动
-- =====================================================================
create table if not exists public.activities (
  activity_id text primary key,
  name        text not null,
  start_time  timestamptz not null,
  end_time    timestamptz not null
);

-- =====================================================================
-- 2. 卡牌（含种类 category：elixir 圣水 / dark_elixir 暗黑重油 /
--    builder_base 建筑大师基地 / super_troop 超级兵种）
--    交换规则：只有同种类（category 相同）的卡牌才能互相交换
-- =====================================================================
create table if not exists public.cards (
  card_id     text primary key,
  activity_id text not null references public.activities(activity_id),
  name        text not null,
  category    text not null default 'elixir',
  image_url   text,                 -- 如 'images/cards/e01.png'（不带前导 /）
  sort_order  integer not null default 0
);
create index if not exists idx_cards_activity on public.cards(activity_id);
create index if not exists idx_cards_category on public.cards(category);

-- =====================================================================
-- 3. 部落
-- =====================================================================
create table if not exists public.clans (
  clan_id uuid primary key default gen_random_uuid(),
  name    text not null unique
);

-- =====================================================================
-- 4. 玩家
-- =====================================================================
create table if not exists public.players (
  player_id       uuid primary key default gen_random_uuid(),
  clan_id         uuid not null references public.clans(clan_id),
  player_tag      text,                       -- 部落冲突玩家标签 #XXXX（可选）
  game_name       text not null,
  access_code     text,                       -- 访问码（可选，用于其他设备换绑）
  keep_base       integer not null default 1, -- 每种卡保留基数，默认 1
  owner_user_id   uuid,                       -- 绑定的 Supabase 匿名用户 ID
  last_updated_at timestamptz not null default now(),
  created_at      timestamptz not null default now(),
  unique (clan_id, player_tag),
  unique (clan_id, game_name)
);

-- =====================================================================
-- 5. 玩家卡牌库存（核心表）
-- =====================================================================
create table if not exists public.player_cards (
  player_id  uuid not null references public.players(player_id),
  card_id    text not null references public.cards(card_id),
  quantity   integer not null default 0 check (quantity >= 0),
  updated_at timestamptz not null default now(),
  primary key (player_id, card_id)
);
create index if not exists idx_player_cards_card   on public.player_cards(card_id);
create index if not exists idx_player_cards_player on public.player_cards(player_id);

-- =====================================================================
-- 6. Row Level Security
-- =====================================================================
alter table public.activities  enable row level security;
alter table public.cards       enable row level security;
alter table public.clans       enable row level security;
alter table public.players     enable row level security;
alter table public.player_cards enable row level security;

-- 读：匿名登录用户可读全部（部落数据共享，用于换卡匹配）
drop policy if exists "activities_select_all"  on public.activities;
drop policy if exists "cards_select_all"       on public.cards;
drop policy if exists "clans_select_all"       on public.clans;
drop policy if exists "players_select_all"     on public.players;
drop policy if exists "player_cards_select_all" on public.player_cards;

create policy "activities_select_all" on public.activities
  for select using (true);
create policy "cards_select_all" on public.cards
  for select using (true);
create policy "clans_select_all" on public.clans
  for select using (true);
create policy "players_select_all" on public.players
  for select using (true);
create policy "player_cards_select_all" on public.player_cards
  for select using (true);

-- 写：只能修改自己绑定（owner_user_id = 当前匿名用户）的玩家数据
drop policy if exists "players_update_own" on public.players;
drop policy if exists "players_delete_own" on public.players;
drop policy if exists "player_cards_insert_own" on public.player_cards;
drop policy if exists "player_cards_update_own" on public.player_cards;
drop policy if exists "player_cards_delete_own" on public.player_cards;

create policy "players_update_own" on public.players
  for update using (owner_user_id = auth.uid());

create policy "players_delete_own" on public.players
  for delete using (owner_user_id = auth.uid());

create policy "player_cards_insert_own" on public.player_cards
  for insert with check (
    exists (
      select 1 from public.players p
      where p.player_id = player_cards.player_id
        and (p.owner_user_id = auth.uid() or p.access_code is null or p.access_code = '')
    )
  );

create policy "player_cards_update_own" on public.player_cards
  for update using (
    exists (
      select 1 from public.players p
      where p.player_id = player_cards.player_id
        and (p.owner_user_id = auth.uid() or p.access_code is null or p.access_code = '')
    )
  );

create policy "player_cards_delete_own" on public.player_cards
  for delete using (
    exists (
      select 1 from public.players p
      where p.player_id = player_cards.player_id
        and (p.owner_user_id = auth.uid() or p.access_code is null or p.access_code = '')
    )
  );

-- =====================================================================
-- 7. 登录/进入 RPC（SECURITY DEFINER：单事务内找/建部落、找/建玩家、初始化库存）
-- =====================================================================
create or replace function public.login_player(
  p_clan_name   text,
  p_player_name text,
  p_player_tag  text default null,
  p_access_code text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_clan_id  uuid;
  v_player   public.players%rowtype;
  v_uid      uuid := auth.uid();
  v_card     record;
  v_editable boolean;
begin
  if v_uid is null then
    raise exception '未登录：请先在 Supabase Auth 中启用匿名登录（Allow anonymous sign-ins）';
  end if;

  -- 1) 部落：找不到就创建
  select clan_id into v_clan_id from public.clans where name = p_clan_name;
  if v_clan_id is null then
    insert into public.clans (name) values (p_clan_name)
    returning clan_id into v_clan_id;
  end if;

  -- 2) 玩家：优先按玩家标签找，其次按名称找
  if p_player_tag is not null and p_player_tag <> '' then
    select * into v_player
    from public.players
    where clan_id = v_clan_id and player_tag = p_player_tag
    limit 1;

    if v_player.player_id is null then
      select * into v_player
      from public.players
      where clan_id = v_clan_id and game_name = p_player_name
      limit 1;
      if v_player.player_id is not null and v_player.player_tag is null then
        update public.players
        set player_tag = p_player_tag, last_updated_at = now()
        where player_id = v_player.player_id;
        v_player.player_tag := p_player_tag;
      end if;
    end if;
  else
    select * into v_player
    from public.players
    where clan_id = v_clan_id and game_name = p_player_name
    limit 1;
  end if;

  -- 3) 新建玩家并初始化当前活动库存
  if v_player.player_id is null then
    insert into public.players (clan_id, player_tag, game_name, owner_user_id, access_code)
    values (v_clan_id, nullif(p_player_tag, ''), p_player_name, v_uid, nullif(p_access_code, ''))
    returning * into v_player;

    for v_card in
      select c.card_id
      from public.cards c
      where c.activity_id = (
        select a.activity_id
        from public.activities a
        order by (case when now() between a.start_time and a.end_time then 0 else 1 end),
                 a.start_time desc
        limit 1
      )
    loop
      insert into public.player_cards (player_id, card_id, quantity)
      values (v_player.player_id, v_card.card_id, 0);
    end loop;
  end if;

  -- 4) 未绑定任何用户 → 绑定到当前匿名用户（认领）
  if v_player.owner_user_id is null then
    update public.players
    set owner_user_id = v_uid, last_updated_at = now()
    where player_id = v_player.player_id;
    v_player.owner_user_id := v_uid;
  end if;

  -- 5) 可编辑性判定：未设置访问码 → 开放编辑；已设置 → 仅主人或输入正确访问码
  v_editable := (v_player.access_code is null or v_player.access_code = '')
                or (v_player.owner_user_id = v_uid);

  -- 5.5) 登录时设置访问码：玩家当前未设码，且本次登录填了访问码 → 设置并成为主人
  if v_editable
     and (v_player.access_code is null or v_player.access_code = '')
     and p_access_code is not null and p_access_code <> '' then
    update public.players
    set access_code = p_access_code, owner_user_id = v_uid, last_updated_at = now()
    where player_id = v_player.player_id;
    v_player.access_code := p_access_code;
    v_player.owner_user_id := v_uid;
  end if;

  -- 6) 访问码换绑：已设置访问码且非主人时，输入正确访问码 → 绑定当前用户
  if not v_editable
     and p_access_code is not null and p_access_code <> ''
     and v_player.access_code is not null and v_player.access_code <> ''
     and v_player.access_code = p_access_code then
    update public.players
    set owner_user_id = v_uid, last_updated_at = now()
    where player_id = v_player.player_id;
    v_player.owner_user_id := v_uid;
    v_editable := true;
  end if;

  return jsonb_build_object(
    'player_id',        v_player.player_id,
    'clan_id',          v_player.clan_id,
    'clan_name',        p_clan_name,
    'player_tag',       v_player.player_tag,
    'game_name',        v_player.game_name,
    'keep_base',        v_player.keep_base,
    'owner_user_id',    v_player.owner_user_id,
    'access_code_set',  (v_player.access_code is not null and v_player.access_code <> ''),
    'editable',         v_editable,
    'last_updated_at',  v_player.last_updated_at
  );
end;
$$;

-- =====================================================================
-- 7.1 设置/修改/清除访问码 RPC
--     未设置访问码 → 任何登录用户都可设置并成为"主人"；
--     已设置访问码 → 仅当前主人可修改或清除。
-- =====================================================================
create or replace function public.set_access_code(
  p_player_id uuid,
  p_new_code  text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player   public.players%rowtype;
  v_uid      uuid := auth.uid();
  v_has_code boolean;
begin
  if v_uid is null then
    raise exception '未登录';
  end if;

  select * into v_player
  from public.players
  where player_id = p_player_id;

  if v_player.player_id is null then
    raise exception '玩家不存在';
  end if;

  v_has_code := (v_player.access_code is not null and v_player.access_code <> '');

  -- 已设置访问码 → 仅主人可修改/清除
  if v_has_code and v_player.owner_user_id <> v_uid then
    raise exception '该玩家已设置访问码，仅主人可修改';
  end if;

  update public.players
  set access_code   = nullif(p_new_code, ''),
      owner_user_id = v_uid,
      last_updated_at = now()
  where player_id = p_player_id;

  select * into v_player
  from public.players
  where player_id = p_player_id;

  return jsonb_build_object(
    'player_id',       v_player.player_id,
    'access_code_set', (v_player.access_code is not null and v_player.access_code <> ''),
    'editable',        true
  );
end;
$$;
-- =====================================================================
-- 8. 种子数据（真实活动与 60 张卡牌）
-- =====================================================================
insert into public.activities (activity_id, name, start_time, end_time)
values (
  'card_clash_2026_08',
  '卡牌冲突 2026年8月',
  '2026-08-01T00:00:00+08:00',
  '2026-08-31T23:59:59+08:00'
)
on conflict (activity_id) do nothing;

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

-- =====================================================================
-- 9. 一键交换：exchanges 表 + execute_exchange RPC
--     换卡双方任意一人点击按钮即可原子完成数据同步；重复点击被拦截。
-- =====================================================================
create table if not exists public.exchanges (
  exchange_id     uuid primary key default gen_random_uuid(),
  activity_id     text not null references public.activities(activity_id),
  player_a        uuid not null references public.players(player_id),
  player_b        uuid not null references public.players(player_id),
  card_from_a     text not null references public.cards(card_id),
  card_from_b     text not null references public.cards(card_id),
  created_by_user uuid,
  created_at      timestamptz not null default now(),
  check (player_a < player_b)
);

create unique index if not exists uq_exchanges_swap
  on public.exchanges (activity_id, player_a, player_b, card_from_a, card_from_b);

create index if not exists idx_exchanges_activity on public.exchanges(activity_id);

alter table public.exchanges enable row level security;

drop policy if exists "exchanges_select_all" on public.exchanges;
create policy "exchanges_select_all" on public.exchanges
  for select using (true);

create or replace function public.execute_exchange(
  p_activity_id text,
  p_player_a    uuid,
  p_player_b    uuid,
  p_card_from_a text,
  p_card_from_b text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid          uuid := auth.uid();
  v_a            uuid;
  v_b            uuid;
  v_ca           text;
  v_cb           text;
  v_row_a        public.players%rowtype;
  v_row_b        public.players%rowtype;
  v_card_a       public.cards%rowtype;
  v_card_b       public.cards%rowtype;
  v_act          public.activities%rowtype;
  v_exchange_id  uuid;
  v_updated      jsonb;
begin
  if v_uid is null then
    raise exception '未登录';
  end if;
  if p_player_a = p_player_b then
    raise exception '不能与自己交换';
  end if;

  select * into v_act from public.activities where activity_id = p_activity_id;
  if v_act.activity_id is null then
    raise exception '活动不存在';
  end if;
  if now() < v_act.start_time or now() > v_act.end_time then
    raise exception '活动已结束，无法交换';
  end if;

  if p_player_a < p_player_b then
    v_a := p_player_a; v_b := p_player_b;
    v_ca := p_card_from_a; v_cb := p_card_from_b;
  else
    v_a := p_player_b; v_b := p_player_a;
    v_ca := p_card_from_b; v_cb := p_card_from_a;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_activity_id::text || '|' || v_a::text || '|' || v_b::text || '|' || v_ca || '|' || v_cb, 0
  ));

  perform 1 from public.exchanges
   where activity_id = p_activity_id and player_a = v_a and player_b = v_b
     and card_from_a = v_ca and card_from_b = v_cb;
  if found then
    return jsonb_build_object('status', 'already_done');
  end if;

  select * into v_row_a from public.players where player_id = v_a;
  select * into v_row_b from public.players where player_id = v_b;
  if v_row_a.player_id is null or v_row_b.player_id is null then
    raise exception '玩家不存在';
  end if;

  if not exists (
    select 1 from public.players p
    where p.player_id in (v_a, v_b) and p.owner_user_id = v_uid
  ) then
    raise exception '无权执行该交换（需为交换双方之一）';
  end if;

  select * into v_card_a from public.cards where card_id = v_ca and activity_id = p_activity_id;
  select * into v_card_b from public.cards where card_id = v_cb and activity_id = p_activity_id;
  if v_card_a.card_id is null or v_card_b.card_id is null then
    raise exception '卡牌不属于当前活动';
  end if;
  if v_card_a.category <> v_card_b.category then
    raise exception '不同种类的卡牌不能交换（% 与 %）', v_card_a.name, v_card_b.name;
  end if;

  update public.player_cards pc
     set quantity = pc.quantity - 1, updated_at = now()
    from public.players p
   where pc.player_id = p.player_id
     and pc.player_id = v_a and pc.card_id = v_ca
     and pc.quantity - p.keep_base > 0;
  if not found then
    raise exception '你已没有多余的「%」可交换', v_card_a.name;
  end if;

  update public.player_cards pc
     set quantity = pc.quantity - 1, updated_at = now()
    from public.players p
   where pc.player_id = p.player_id
     and pc.player_id = v_b and pc.card_id = v_cb
     and pc.quantity - p.keep_base > 0;
  if not found then
    raise exception '对方已没有多余的「%」可交换', v_card_b.name;
  end if;

  insert into public.player_cards (player_id, card_id, quantity, updated_at)
  values (v_a, v_cb, 1, now())
  on conflict (player_id, card_id)
  do update set quantity = public.player_cards.quantity + 1, updated_at = now();

  insert into public.player_cards (player_id, card_id, quantity, updated_at)
  values (v_b, v_ca, 1, now())
  on conflict (player_id, card_id)
  do update set quantity = public.player_cards.quantity + 1, updated_at = now();

  update public.players set last_updated_at = now() where player_id in (v_a, v_b);

  insert into public.exchanges
    (activity_id, player_a, player_b, card_from_a, card_from_b, created_by_user)
  values (p_activity_id, v_a, v_b, v_ca, v_cb, v_uid)
  returning exchange_id into v_exchange_id;

  select jsonb_agg(jsonb_build_object(
    'player_id', pc.player_id,
    'card_id',   pc.card_id,
    'quantity',  pc.quantity
  ))
  into v_updated
  from public.player_cards pc
  where (pc.player_id = v_a and pc.card_id in (v_ca, v_cb))
     or (pc.player_id = v_b and pc.card_id in (v_ca, v_cb));

  return jsonb_build_object(
    'status',      'ok',
    'exchange_id', v_exchange_id,
    'updated',     coalesce(v_updated, '[]'::jsonb)
  );
end;
$$;