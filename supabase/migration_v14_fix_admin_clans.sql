-- =====================================================================
-- 迁移 v14：修复 admin_list_clans（clans 表没有 created_at 列）
-- ---------------------------------------------------------------------
-- 已执行 v13 的数据库执行本迁移即可修复后台「部落管理」报错。
-- 在 Supabase SQL Editor 中整体执行即可（可重复执行）。
-- =====================================================================
-- 8.4 部落列表
create or replace function public.admin_list_clans(p_admin_code text)
returns table(clan_id uuid, name text, member_count bigint)
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.admin_check_code(p_admin_code);
  return query
    select c.clan_id, c.name, count(p.player_id)::bigint
    from public.clans c
    left join public.players p on p.clan_id = c.clan_id
    group by c.clan_id
    order by c.name asc;
end;
$$;