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
  channel         text not null default 'wechat', -- 登录渠道：wechat 微信区 / qq QQ区
  matchable       boolean not null default true, -- 可被匹配开关（关=不出现在他人推荐中）
  banned          boolean not null default false, -- 被管理员禁用（禁用后不可登录/交换）
  last_login_at   timestamptz, -- 最后登录时间
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
  p_access_code text default null,
  p_channel     text default 'wechat'
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

  -- 7) 登录渠道（区服）：默认微信区，可在登录页修改；仅影响匹配结果
  if p_channel is not null and p_channel <> '' then
    update public.players
    set channel = p_channel, last_updated_at = now()
    where player_id = v_player.player_id;
    v_player.channel := p_channel;
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
    'channel',          v_player.channel,
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
-- 7.2 切换「可被匹配」开关 RPC（默认开启；关闭后不出现在他人推荐中）
-- =====================================================================
create or replace function public.set_matchable(p_player_id uuid, p_matchable boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception '未登录';
  end if;
  if not exists (
    select 1 from public.players p
    where p.player_id = p_player_id
      and (p.owner_user_id = v_uid or p.access_code is null or p.access_code = '')
  ) then
    raise exception '无权修改该玩家的匹配设置';
  end if;

  update public.players
  set matchable = p_matchable, last_updated_at = now()
  where player_id = p_player_id;

  return jsonb_build_object('player_id', p_player_id, 'matchable', p_matchable);
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
    where p.player_id in (v_a, v_b)
      and (p.owner_user_id = v_uid or p.access_code is null or p.access_code = '')
  ) then
    raise exception '无权执行该交换（需为交换双方之一，或对方为未设访问码的开放账号）';
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

-- =====================================================================
-- 10. 撤销交换：undo_exchange RPC
--     误点「交换完成」后，交换双方之一可撤销，恢复双方卡牌数量。
-- =====================================================================
create or replace function public.undo_exchange(
  p_exchange_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid         uuid := auth.uid();
  v_ex          public.exchanges%rowtype;
  v_qa_from_b   integer;
  v_qb_from_a   integer;
  v_updated     jsonb;
begin
  if v_uid is null then
    raise exception '未登录';
  end if;

  select * into v_ex from public.exchanges where exchange_id = p_exchange_id;
  if v_ex.exchange_id is null then
    raise exception '交换记录不存在';
  end if;

  if not exists (
    select 1 from public.players p
    where p.player_id in (v_ex.player_a, v_ex.player_b)
      and (p.owner_user_id = v_uid or p.access_code is null or p.access_code = '')
  ) then
    raise exception '无权撤销该交换（需为交换双方之一，或对方为未设访问码的开放账号）';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('undo:' || p_exchange_id::text, 0));

  select coalesce(quantity, 0) into v_qa_from_b
    from public.player_cards
   where player_id = v_ex.player_a and card_id = v_ex.card_from_b;
  if v_qa_from_b <= 0 then
    raise exception '撤销失败：该交换的卡已被用于其他交换，无法撤销';
  end if;

  select coalesce(quantity, 0) into v_qb_from_a
    from public.player_cards
   where player_id = v_ex.player_b and card_id = v_ex.card_from_a;
  if v_qb_from_a <= 0 then
    raise exception '撤销失败：该交换的卡已被用于其他交换，无法撤销';
  end if;

  update public.player_cards
     set quantity = quantity - 1, updated_at = now()
   where player_id = v_ex.player_a and card_id = v_ex.card_from_b and quantity > 0;

  update public.player_cards
     set quantity = quantity + 1, updated_at = now()
   where player_id = v_ex.player_a and card_id = v_ex.card_from_a;

  update public.player_cards
     set quantity = quantity - 1, updated_at = now()
   where player_id = v_ex.player_b and card_id = v_ex.card_from_a and quantity > 0;

  update public.player_cards
     set quantity = quantity + 1, updated_at = now()
   where player_id = v_ex.player_b and card_id = v_ex.card_from_b;

  update public.players set last_updated_at = now() where player_id in (v_ex.player_a, v_ex.player_b);

  delete from public.exchanges where exchange_id = p_exchange_id;

  select jsonb_agg(jsonb_build_object(
    'player_id', pc.player_id,
    'card_id',   pc.card_id,
    'quantity',  pc.quantity
  ))
  into v_updated
  from public.player_cards pc
  where (pc.player_id = v_ex.player_a and pc.card_id in (v_ex.card_from_a, v_ex.card_from_b))
     or (pc.player_id = v_ex.player_b and pc.card_id in (v_ex.card_from_a, v_ex.card_from_b));

  return jsonb_build_object(
    'status',      'ok',
    'updated',     coalesce(v_updated, '[]'::jsonb)
  );
end;
$$;

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ---------- 1. 通知设置表（邮箱只存这里，不放在 players，避免被匿名读取） ----------
create table if not exists public.notification_settings (
  player_id      uuid primary key references public.players(player_id),
  email          text,
  enabled        boolean not null default false,
  scope          text not null default 'twoWay',  -- twoWay 仅双向 | all 双向+单向
  last_has       boolean not null default false,  -- 上次检查是否有可交换卡牌（用于"从无到有"才发）
  last_checked_at timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
alter table public.notification_settings enable row level security;

-- ---------- 2. 邮件发送记录（备查） ----------
create table if not exists public.email_queue (
  id         bigint generated always as identity primary key,
  player_id  uuid references public.players(player_id),
  to_email   text not null,
  subject    text not null,
  body       text not null,
  created_at timestamptz not null default now()
);
alter table public.email_queue enable row level security;

-- ---------- 3. 系统配置（SendGrid 密钥等，仅 postgres 可见） ----------
create table if not exists public.app_config (
  key   text primary key,
  value text not null
);
alter table public.app_config enable row level security;

-- ---------- 4. 读取通知设置 RPC ----------
create or replace function public.get_notification_settings(p_player_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_ns  record;
begin
  if v_uid is null then
    raise exception '未登录';
  end if;
  if not exists (
    select 1 from public.players p
    where p.player_id = p_player_id
      and (p.owner_user_id = v_uid or p.access_code is null or p.access_code = '')
  ) then
    raise exception '无权查看该玩家的通知设置';
  end if;

  select * into v_ns from public.notification_settings where player_id = p_player_id;
  if v_ns.player_id is null then
    return jsonb_build_object('player_id', p_player_id, 'email', null, 'enabled', false, 'scope', 'twoWay');
  end if;
  return jsonb_build_object('player_id', v_ns.player_id, 'email', v_ns.email, 'enabled', v_ns.enabled, 'scope', v_ns.scope);
end;
$$;

-- ---------- 5. 保存通知设置 RPC ----------
create or replace function public.set_notification_settings(
  p_player_id uuid,
  p_email     text,
  p_enabled   boolean,
  p_scope     text default 'twoWay'
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_email text := nullif(btrim(p_email), '');
begin
  if v_uid is null then
    raise exception '未登录';
  end if;
  if not exists (
    select 1 from public.players p
    where p.player_id = p_player_id
      and (p.owner_user_id = v_uid or p.access_code is null or p.access_code = '')
  ) then
    raise exception '无权修改该玩家的通知设置';
  end if;
  if p_enabled and v_email is null then
    raise exception '开启通知必须填写邮箱';
  end if;
  if p_scope not in ('twoWay', 'all') then
    p_scope := 'twoWay';
  end if;

  insert into public.notification_settings (player_id, email, enabled, scope)
  values (p_player_id, v_email, p_enabled, p_scope)
  on conflict (player_id) do update
    set email     = excluded.email,
        enabled   = excluded.enabled,
        scope     = excluded.scope,
        last_has  = case
                      when public.notification_settings.email is distinct from excluded.email then false
                      else public.notification_settings.last_has
                    end,
        updated_at = now();

  return jsonb_build_object('player_id', p_player_id, 'email', v_email, 'enabled', p_enabled, 'scope', p_scope);
end;
$$;

-- ---------- 6. 定时检查并发送通知 ----------
create or replace function public.notify_check()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key      text;
  v_from     text;
  v_url      text := 'https://chen-chen-99.github.io/coc-change-card/';
  v_rec      record;
  v_has_two  boolean;
  v_has_one  boolean;
  v_has_match boolean;
  v_subject  text;
  v_body     text;
  v_body_j   jsonb;
  v_head_j   jsonb;
begin
  select value into v_key  from public.app_config where key = 'sendgrid_api_key';
  select value into v_from from public.app_config where key = 'sendgrid_from_email';
  if v_key is null or v_from is null then
    raise notice 'SendGrid 未配置（app_config 缺少 sendgrid_api_key / sendgrid_from_email），跳过';
    return;
  end if;

  for v_rec in
    select ns.player_id, p.channel, p.clan_id, p.keep_base, ns.email, ns.scope, ns.last_has
    from public.notification_settings ns
    join public.players p on p.player_id = ns.player_id
    where ns.enabled and ns.email is not null and ns.email <> ''
  loop
    -- 双向：我缺X、对方有多余X、我有同种类多余Y、对方缺Y，且 同渠道 或 同部落
    select exists (
      select 1
      from public.player_cards need
      join public.cards c_need on c_need.card_id = need.card_id
      join public.player_cards pgive on pgive.card_id = need.card_id
      join public.players P on P.player_id = pgive.player_id and P.player_id <> v_rec.player_id
      join public.player_cards ahave on ahave.player_id = v_rec.player_id
      join public.cards c_have on c_have.card_id = ahave.card_id and c_have.category = c_need.category
      join public.player_cards pneed on pneed.player_id = P.player_id and pneed.card_id = ahave.card_id and pneed.quantity = 0
      where need.player_id = v_rec.player_id
        and need.quantity = 0
        and pgive.quantity - P.keep_base > 0
        and ahave.quantity - v_rec.keep_base > 0
        and (P.channel = v_rec.channel or P.clan_id = v_rec.clan_id)
    ) into v_has_two;

    -- 单向：我缺X、对方有多余X、我有同种类多余Y
    select exists (
      select 1
      from public.player_cards need
      join public.cards c_need on c_need.card_id = need.card_id
      join public.player_cards pgive on pgive.card_id = need.card_id
      join public.players P on P.player_id = pgive.player_id and P.player_id <> v_rec.player_id
      join public.player_cards ahave on ahave.player_id = v_rec.player_id
      join public.cards c_have on c_have.card_id = ahave.card_id and c_have.category = c_need.category
      where need.player_id = v_rec.player_id
        and need.quantity = 0
        and pgive.quantity - P.keep_base > 0
        and ahave.quantity - v_rec.keep_base > 0
        and (P.channel = v_rec.channel or P.clan_id = v_rec.clan_id)
    ) into v_has_one;

    v_has_match := case when v_rec.scope = 'twoWay' then v_has_two else (v_has_two or v_has_one) end;

    -- 从"无"到"有"才发送一封邮件
    if v_has_match and not v_rec.last_has then
      v_subject := '【卡牌冲突】你有可交换的卡牌了！';
      v_body := '你当前有' || case when v_rec.scope = 'twoWay' then '可双向交换' else '可交换' end
             || '的卡牌，请登录系统查看具体内容：' || v_url;

      insert into public.email_queue (player_id, to_email, subject, body)
      values (v_rec.player_id, v_rec.email, v_subject, v_body);

      v_body_j := jsonb_build_object(
        'personalizations', jsonb_build_array(
          jsonb_build_object('to', jsonb_build_array(jsonb_build_object('email', v_rec.email)))
        ),
        'from', jsonb_build_object('email', v_from),
        'subject', v_subject,
        'content', jsonb_build_array(jsonb_build_object('type', 'text/plain', 'value', v_body))
      );
      v_head_j := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json');

      perform net.http_post(
        'https://api.sendgrid.com/v3/mail/send',
        v_body_j,
        '{}'::jsonb,
        v_head_j
      );
    end if;

    update public.notification_settings
    set last_has = v_has_match, last_checked_at = now()
    where player_id = v_rec.player_id;
  end loop;
end;
$$;

-- ---------- 7. 每 30 分钟执行一次 ----------
select cron.schedule('notify-check-30min', '*/30 * * * *', $$select public.notify_check()$$);

-- =====================================================================
-- 配置 SendGrid（执行完上面的内容后，再单独执行下面两条，把值换成你自己的）：
--
--   insert into public.app_config (key, value) values
--   ('sendgrid_api_key',     'SG.你的SendGrid_API密钥'),
--   ('sendgrid_from_email',  '你的已认证发件人@example.com')
--   on conflict (key) do update set value = excluded.value;
--
-- 说明：
--   - SendGrid 免费版：100 封/天，够用；
--   - 发件人需在 SendGrid 后台做"单发件人验证"（Single Sender Verification），
--     无需域名，用你自己的邮箱即可；
--   - API Key 建议只勾选 "Mail Send" 权限（最小权限）。
-- =====================================================================

-- =====================================================================
-- ▼▼▼ 以下为 v13「后台管理」同步内容（覆盖上文同名函数/策略，请勿删除）▼▼▼
-- =====================================================================
-- =====================================================================
-- 迁移 v13：后台管理（admin）
-- ---------------------------------------------------------------------
-- 功能：
--   1. 玩家表新增 banned（禁用）与 last_login_at（最后登录时间）；
--   2. login_player：禁用玩家登录时抛出提示（请加群 / 联系开发者）；
--   3. 一键交换 / 撤销交换 / 库存写入：禁用玩家一律拦截；
--   4. 后台管理 RPC（管理员口令校验后可用）：
--      admin_verify / admin_stats / admin_list_players / admin_list_clans
--      admin_set_banned / admin_delete_player / admin_delete_clan
-- 管理员口令存在 app_config.admin_code，本迁移已生成默认口令，
-- 执行后请【务必修改】为你自己的口令（见文件末尾说明）。
-- 在 Supabase SQL Editor 中整体执行即可（可重复执行）。
-- =====================================================================

-- ---------- 1. 玩家表新增列 ----------
alter table public.players add column if not exists banned boolean not null default false;
alter table public.players add column if not exists last_login_at timestamptz;

-- ---------- 2. 默认管理员口令（已生成；执行后请务必修改） ----------
insert into public.app_config (key, value)
values ('admin_code', 'eOtm48EZ7My5Ls')
on conflict (key) do nothing;

-- ---------- 3. 口令校验助手（供各 admin RPC 调用） ----------
create or replace function public.admin_check_code(p_admin_code text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_code text;
begin
  select value into v_code from public.app_config where key = 'admin_code';
  if v_code is null or v_code = '' or p_admin_code is distinct from v_code then
    raise exception '管理员口令错误';
  end if;
end;
$$;

-- ---------- 4. login_player：禁用拦截 + 记录最后登录时间 ----------
create or replace function public.login_player(
  p_clan_name   text,
  p_player_name text,
  p_player_tag  text default null,
  p_access_code text default null,
  p_channel     text default 'wechat'
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

  -- 3.5) 禁用拦截：被管理员禁用的玩家不允许登录
  if v_player.banned then
    raise exception '该账号已被禁用：使用前请先加入对应渠道的群，或联系开发者（QQ 1456734671 · 部落号 #29UL9PRJR）';
  end if;

  -- 4) 未绑定任何用户 → 绑定到当前匿名用户（认领）
  if v_player.owner_user_id is null then
    update public.players
    set owner_user_id = v_uid, last_updated_at = now()
    where player_id = v_player.player_id;
    v_player.owner_user_id := v_uid;
  end if;

  -- 5) 可编辑性判定
  v_editable := (v_player.access_code is null or v_player.access_code = '')
                or (v_player.owner_user_id = v_uid);

  -- 5.5) 登录时设置访问码
  if v_editable
     and (v_player.access_code is null or v_player.access_code = '')
     and p_access_code is not null and p_access_code <> '' then
    update public.players
    set access_code = p_access_code, owner_user_id = v_uid, last_updated_at = now()
    where player_id = v_player.player_id;
    v_player.access_code := p_access_code;
    v_player.owner_user_id := v_uid;
  end if;

  -- 6) 访问码换绑
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

  -- 7) 登录渠道（区服）
  if p_channel is not null and p_channel <> '' then
    update public.players
    set channel = p_channel, last_updated_at = now()
    where player_id = v_player.player_id;
    v_player.channel := p_channel;
  end if;

  -- 8) 记录最后登录时间
  update public.players
  set last_login_at = now()
  where player_id = v_player.player_id;
  v_player.last_login_at := now();

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
    'channel',          v_player.channel,
    'banned',           v_player.banned,
    'last_login_at',    v_player.last_login_at,
    'last_updated_at',  v_player.last_updated_at
  );
end;
$$;
-- ---------- 5. execute_exchange：禁用玩家不可执行交换 ----------
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
    where p.player_id in (v_a, v_b)
      and (p.owner_user_id = v_uid or p.access_code is null or p.access_code = '')
      and not p.banned
  ) then
    raise exception '无权执行该交换（需为交换双方之一，或对方为未设访问码的开放账号）';
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

-- ---------- 6. undo_exchange：禁用玩家不可撤销 ----------
create or replace function public.undo_exchange(
  p_exchange_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid         uuid := auth.uid();
  v_ex          public.exchanges%rowtype;
  v_qa_from_b   integer;
  v_qb_from_a   integer;
  v_updated     jsonb;
begin
  if v_uid is null then
    raise exception '未登录';
  end if;

  select * into v_ex from public.exchanges where exchange_id = p_exchange_id;
  if v_ex.exchange_id is null then
    raise exception '交换记录不存在';
  end if;

  if not exists (
    select 1 from public.players p
    where p.player_id in (v_ex.player_a, v_ex.player_b)
      and (p.owner_user_id = v_uid or p.access_code is null or p.access_code = '')
      and not p.banned
  ) then
    raise exception '无权撤销该交换（需为交换双方之一，或对方为未设访问码的开放账号）';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('undo:' || p_exchange_id::text, 0));

  select coalesce(quantity, 0) into v_qa_from_b
    from public.player_cards
   where player_id = v_ex.player_a and card_id = v_ex.card_from_b;
  if v_qa_from_b <= 0 then
    raise exception '撤销失败：该交换的卡已被用于其他交换，无法撤销';
  end if;

  select coalesce(quantity, 0) into v_qb_from_a
    from public.player_cards
   where player_id = v_ex.player_b and card_id = v_ex.card_from_a;
  if v_qb_from_a <= 0 then
    raise exception '撤销失败：该交换的卡已被用于其他交换，无法撤销';
  end if;

  update public.player_cards
     set quantity = quantity - 1, updated_at = now()
   where player_id = v_ex.player_a and card_id = v_ex.card_from_b and quantity > 0;

  update public.player_cards
     set quantity = quantity + 1, updated_at = now()
   where player_id = v_ex.player_a and card_id = v_ex.card_from_a;

  update public.player_cards
     set quantity = quantity - 1, updated_at = now()
   where player_id = v_ex.player_b and card_id = v_ex.card_from_a and quantity > 0;

  update public.player_cards
     set quantity = quantity + 1, updated_at = now()
   where player_id = v_ex.player_b and card_id = v_ex.card_from_b;

  update public.players set last_updated_at = now() where player_id in (v_ex.player_a, v_ex.player_b);

  delete from public.exchanges where exchange_id = p_exchange_id;

  select jsonb_agg(jsonb_build_object(
    'player_id', pc.player_id,
    'card_id',   pc.card_id,
    'quantity',  pc.quantity
  ))
  into v_updated
  from public.player_cards pc
  where (pc.player_id = v_ex.player_a and pc.card_id in (v_ex.card_from_a, v_ex.card_from_b))
     or (pc.player_id = v_ex.player_b and pc.card_id in (v_ex.card_from_a, v_ex.card_from_b));

  return jsonb_build_object('status', 'ok', 'updated', coalesce(v_updated, '[]'::jsonb));
end;
$$;
-- ---------- 7. RLS：禁用玩家不可写入库存 / 修改资料 ----------
drop policy if exists "players_update_own" on public.players;
create policy "players_update_own" on public.players
  for update using (owner_user_id = auth.uid() and not banned);

drop policy if exists "player_cards_insert_own" on public.player_cards;
create policy "player_cards_insert_own" on public.player_cards
  for insert with check (
    exists (
      select 1 from public.players p
      where p.player_id = player_cards.player_id
        and (p.owner_user_id = auth.uid() or p.access_code is null or p.access_code = '')
        and not p.banned
    )
  );

drop policy if exists "player_cards_update_own" on public.player_cards;
create policy "player_cards_update_own" on public.player_cards
  for update using (
    exists (
      select 1 from public.players p
      where p.player_id = player_cards.player_id
        and (p.owner_user_id = auth.uid() or p.access_code is null or p.access_code = '')
        and not p.banned
    )
  );

drop policy if exists "player_cards_delete_own" on public.player_cards;
create policy "player_cards_delete_own" on public.player_cards
  for delete using (
    exists (
      select 1 from public.players p
      where p.player_id = player_cards.player_id
        and (p.owner_user_id = auth.uid() or p.access_code is null or p.access_code = '')
        and not p.banned
    )
  );

-- ---------- 8. 后台管理 RPC 全套 ----------

-- 8.1 校验口令
create or replace function public.admin_verify(p_admin_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.admin_check_code(p_admin_code);
  return jsonb_build_object('ok', true);
end;
$$;

-- 8.2 概览统计
create or replace function public.admin_stats(p_admin_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_players int; v_clans int; v_exchanges int; v_banned int;
  v_wechat int; v_qq int; v_wechat_matchable int; v_qq_matchable int;
begin
  perform public.admin_check_code(p_admin_code);
  select count(*) into v_players from public.players;
  select count(*) into v_clans from public.clans;
  select count(*) into v_exchanges from public.exchanges;
  select count(*) into v_banned from public.players where banned;
  select count(*) into v_wechat from public.players where channel = 'wechat';
  select count(*) into v_qq from public.players where channel = 'qq';
  select count(*) into v_wechat_matchable from public.players where channel = 'wechat' and matchable;
  select count(*) into v_qq_matchable from public.players where channel = 'qq' and matchable;
  return jsonb_build_object(
    'players', v_players, 'clans', v_clans, 'exchanges', v_exchanges, 'banned', v_banned,
    'channel_wechat', v_wechat, 'channel_qq', v_qq,
    'matchable_wechat', v_wechat_matchable, 'matchable_qq', v_qq_matchable
  );
end;
$$;

-- 8.3 玩家列表（含部落名 / 已录数据 / 最后登录）
create or replace function public.admin_list_players(p_admin_code text)
returns table(
  player_id uuid, game_name text, player_tag text, channel text,
  banned boolean, matchable boolean, keep_base integer,
  access_code_set boolean, clan_id uuid, clan_name text,
  last_login_at timestamptz, last_updated_at timestamptz,
  data_rows bigint, owned_cards bigint
)
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.admin_check_code(p_admin_code);
  return query
    select p.player_id, p.game_name, p.player_tag, p.channel,
           p.banned, p.matchable, p.keep_base,
           (p.access_code is not null and p.access_code <> ''),
           p.clan_id, c.name,
           p.last_login_at, p.last_updated_at,
           count(pc.card_id)::bigint,
           count(pc.card_id) filter (where pc.quantity > 0)::bigint
    from public.players p
    left join public.clans c on c.clan_id = p.clan_id
    left join public.player_cards pc on pc.player_id = p.player_id
    group by p.player_id, c.clan_id, c.name
    order by p.last_login_at desc nulls last, p.game_name;
end;
$$;

-- 8.4 部落列表
create or replace function public.admin_list_clans(p_admin_code text)
returns table(clan_id uuid, name text, member_count bigint, created_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.admin_check_code(p_admin_code);
  return query
    select c.clan_id, c.name, count(p.player_id)::bigint, c.created_at
    from public.clans c
    left join public.players p on p.clan_id = c.clan_id
    group by c.clan_id
    order by c.created_at asc;
end;
$$;

-- 8.5 禁用 / 启用用户
create or replace function public.admin_set_banned(p_admin_code text, p_player_id uuid, p_banned boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.admin_check_code(p_admin_code);
  update public.players set banned = p_banned where player_id = p_player_id;
  return jsonb_build_object('player_id', p_player_id, 'banned', p_banned);
end;
$$;

-- 8.6 删除用户（连同库存 / 换卡记录 / 通知设置）
create or replace function public.admin_delete_player(p_admin_code text, p_player_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.admin_check_code(p_admin_code);
  delete from public.exchanges where player_a = p_player_id or player_b = p_player_id;
  delete from public.notification_settings where player_id = p_player_id;
  delete from public.player_cards where player_id = p_player_id;
  delete from public.players where player_id = p_player_id;
  return jsonb_build_object('deleted', p_player_id);
end;
$$;

-- 8.7 删除部落（连同该部落全部玩家及其数据）
create or replace function public.admin_delete_clan(p_admin_code text, p_clan_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.admin_check_code(p_admin_code);
  delete from public.exchanges e
   using public.players p
   where (e.player_a = p.player_id or e.player_b = p.player_id)
     and p.clan_id = p_clan_id;
  delete from public.notification_settings ns
   using public.players p
   where ns.player_id = p.player_id and p.clan_id = p_clan_id;
  delete from public.player_cards pc
   using public.players p
   where pc.player_id = p.player_id and p.clan_id = p_clan_id;
  delete from public.players where clan_id = p_clan_id;
  delete from public.clans where clan_id = p_clan_id;
  return jsonb_build_object('deleted_clan', p_clan_id);
end;
$$;

-- =====================================================================
-- 修改管理员口令（执行后请执行下面这行，把值换成你自己的）：
--   update public.app_config set value = '你的新口令' where key = 'admin_code';
-- =====================================================================
