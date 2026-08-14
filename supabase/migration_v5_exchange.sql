-- =====================================================================
-- 迁移 v5：一键交换（换卡数据同步）
-- ---------------------------------------------------------------------
-- 新增：
--   1. exchanges 表：记录每次已执行的交换（防重复 + 审计）
--   2. execute_exchange RPC：原子完成一次交换
--      - 校验：同部落、同种类、活动进行中、双方仍有"多余"卡（保留基数后）
--      - 交换双方任意一人点击即可完成；重复点击会被拦截（返回 already_done）
-- 适用：已执行过 migration_v4_login_set_code.sql 的数据库。
-- 在 Supabase SQL Editor 中整体执行。
-- =====================================================================

-- ---------- 1. 交换记录表 ----------
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

-- 同一笔交换只允许执行一次（双方都点击也只记录一条）
create unique index if not exists uq_exchanges_swap
  on public.exchanges (activity_id, player_a, player_b, card_from_a, card_from_b);

create index if not exists idx_exchanges_activity on public.exchanges(activity_id);

alter table public.exchanges enable row level security;

drop policy if exists "exchanges_select_all" on public.exchanges;
create policy "exchanges_select_all" on public.exchanges
  for select using (true);

-- ---------- 2. 一键交换 RPC ----------
create or replace function public.execute_exchange(
  p_activity_id text,
  p_player_a    uuid,
  p_player_b    uuid,
  p_card_from_a text,   -- p_player_a 给 p_player_b 的卡
  p_card_from_b text    -- p_player_b 给 p_player_a 的卡
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

  -- 活动必须存在且正在进行
  select * into v_act from public.activities where activity_id = p_activity_id;
  if v_act.activity_id is null then
    raise exception '活动不存在';
  end if;
  if now() < v_act.start_time or now() > v_act.end_time then
    raise exception '活动已结束，无法交换';
  end if;

  -- 归一化：a 为较小 player_id，保证双方点击产生同一条记录
  if p_player_a < p_player_b then
    v_a := p_player_a; v_b := p_player_b;
    v_ca := p_card_from_a; v_cb := p_card_from_b;
  else
    v_a := p_player_b; v_b := p_player_a;
    v_ca := p_card_from_b; v_cb := p_card_from_a;
  end if;

  -- 串行化同一笔交换（防并发双击重复扣减）
  perform pg_advisory_xact_lock(hashtextextended(
    p_activity_id::text || '|' || v_a::text || '|' || v_b::text || '|' || v_ca || '|' || v_cb, 0
  ));

  -- 防重复：同一笔交换已执行过则直接返回
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
  if v_row_a.clan_id <> v_row_b.clan_id then
    raise exception '只能与同部落成员交换';
  end if;

  -- 权限：点击者必须是交换双方之一（本人账号）
  if not exists (
    select 1 from public.players p
    where p.player_id in (v_a, v_b) and p.owner_user_id = v_uid
  ) then
    raise exception '无权执行该交换（需为交换双方之一）';
  end if;

  -- 卡牌：属于当前活动，且同种类
  select * into v_card_a from public.cards where card_id = v_ca and activity_id = p_activity_id;
  select * into v_card_b from public.cards where card_id = v_cb and activity_id = p_activity_id;
  if v_card_a.card_id is null or v_card_b.card_id is null then
    raise exception '卡牌不属于当前活动';
  end if;
  if v_card_a.category <> v_card_b.category then
    raise exception format('不同种类的卡牌不能交换（%s 与 %s）', v_card_a.name, v_card_b.name);
  end if;

  -- 双方扣减（带余量校验：保留 keep_base 张后仍 > 0）
  update public.player_cards pc
     set quantity = pc.quantity - 1, updated_at = now()
    from public.players p
   where pc.player_id = p.player_id
     and pc.player_id = v_a and pc.card_id = v_ca
     and pc.quantity - p.keep_base > 0;
  if not found then
    raise exception format('你已没有多余的「%s」可交换', v_card_a.name);
  end if;

  update public.player_cards pc
     set quantity = pc.quantity - 1, updated_at = now()
    from public.players p
   where pc.player_id = p.player_id
     and pc.player_id = v_b and pc.card_id = v_cb
     and pc.quantity - p.keep_base > 0;
  if not found then
    raise exception format('对方已没有多余的「%s」可交换', v_card_b.name);
  end if;

  -- 双方入账
  insert into public.player_cards (player_id, card_id, quantity, updated_at)
  values (v_a, v_cb, 1, now())
  on conflict (player_id, card_id)
  do update set quantity = public.player_cards.quantity + 1, updated_at = now();

  insert into public.player_cards (player_id, card_id, quantity, updated_at)
  values (v_b, v_ca, 1, now())
  on conflict (player_id, card_id)
  do update set quantity = public.player_cards.quantity + 1, updated_at = now();

  -- 更新双方"最后更新时间"
  update public.players set last_updated_at = now() where player_id in (v_a, v_b);

  -- 记录交换
  insert into public.exchanges
    (activity_id, player_a, player_b, card_from_a, card_from_b, created_by_user)
  values (p_activity_id, v_a, v_b, v_ca, v_cb, v_uid)
  returning exchange_id into v_exchange_id;

  -- 返回受影响行，供前端更新本地状态
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