-- =====================================================================
-- 迁移 v8：撤销交换（undo_exchange）
-- ---------------------------------------------------------------------
-- 目的：用户误点「交换完成」后可以撤销，恢复双方卡牌数量。
-- 规则：
--   1. 仅交换双方之一（本人账号）可撤销；
--   2. 撤销前校验：双方当前库存足以归还收到的卡（若已被用于其他交换则拒绝）；
--   3. 单事务内完成归还 + 删除交换记录，防止重复撤销。
-- 适用：已执行过 migration_v7_channel.sql 的数据库。
-- 在 Supabase SQL Editor 中整体执行。
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

  -- 权限：撤销者必须是交换双方之一（本人账号）
  if not exists (
    select 1 from public.players p
    where p.player_id in (v_ex.player_a, v_ex.player_b) and p.owner_user_id = v_uid
  ) then
    raise exception '无权撤销该交换（需为交换双方之一）';
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