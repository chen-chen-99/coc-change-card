-- =====================================================================
-- 迁移 v9：修复「开放账号」无法一键交换/撤销的权限 bug
-- ---------------------------------------------------------------------
-- 问题：execute_exchange / undo_exchange 的权限检查只允许「绑定设备
--      （owner_user_id = auth.uid()）」，而改卡牌数量的 RLS 规则是
--      「未设访问码（开放账号）任何设备可操作」。导致未设访问码的
--      玩家换个设备/匿名会话后能改卡，却无法点「交换完成」。
-- 修复：权限判断与改卡规则保持一致——
--      对交换双方之一拥有操作权（绑定设备 或 未设访问码的开放账号）。
-- 适用：已执行过 migration_v8_undo_exchange.sql 的数据库。
-- 在 Supabase SQL Editor 中整体执行。
-- =====================================================================

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

  -- 权限：点击者需对交换双方之一有操作权（绑定设备 或 未设访问码的开放账号）
  if not exists (
    select 1 from public.players p
    where p.player_id in (v_a, v_b)
      and (p.owner_user_id = v_uid or p.access_code is null or p.access_code = '')
  ) then
    raise exception '无权执行该交换（需为交换双方之一，或对方为未设访问码的开放账号）';
  end if;

  -- 卡牌：属于当前活动，且同种类
  select * into v_card_a from public.cards where card_id = v_ca and activity_id = p_activity_id;
  select * into v_card_b from public.cards where card_id = v_cb and activity_id = p_activity_id;
  if v_card_a.card_id is null or v_card_b.card_id is null then
    raise exception '卡牌不属于当前活动';
  end if;
  if v_card_a.category <> v_card_b.category then
    raise exception '不同种类的卡牌不能交换（% 与 %）', v_card_a.name, v_card_b.name;
  end if;

  -- 双方扣减（带余量校验：保留 keep_base 张后仍 > 0）
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

  -- 权限：撤销者需对交换双方之一有操作权（绑定设备 或 未设访问码的开放账号）
  if not exists (
    select 1 from public.players p
    where p.player_id in (v_ex.player_a, v_ex.player_b)
      and (p.owner_user_id = v_uid or p.access_code is null or p.access_code = '')
  ) then
    raise exception '无权撤销该交换（需为交换双方之一，或对方为未设访问码的开放账号）';
  end if;

  -- 串行化同一笔撤销，避免并发重复处理
  perform pg_advisory_xact_lock(hashtextextended('undo:' || p_exchange_id::text, 0));

  -- 校验：双方当前库存足以归还收到的卡
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

  -- 归还：扣回收到的卡、加回给出的卡
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

  -- 删除交换记录，防止重复撤销
  delete from public.exchanges where exchange_id = p_exchange_id;

  -- 返回受影响行，供前端更新本地状态
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