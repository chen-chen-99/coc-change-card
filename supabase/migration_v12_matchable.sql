-- =====================================================================
-- 迁移 v12：玩家「可被匹配」开关
-- ---------------------------------------------------------------------
-- 功能：用户关闭该开关后，将不会出现在其他玩家的换卡推荐 / 凑卡兑换中
--       （避免不想被打扰的用户被反复匹配）。默认开启。
-- 在 Supabase SQL Editor 中整体执行即可（可重复执行）。
-- =====================================================================

-- 1. players 表新增 matchable 列（默认 true = 可被匹配）
alter table public.players add column if not exists matchable boolean not null default true;

-- 2. 切换开关 RPC（与库存修改权限一致：本人 或 开放账号 可改）
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