-- =====================================================================
-- 迁移 v15：后台管理增强（国际服统计 + 可被匹配开关）
-- ---------------------------------------------------------------------
-- 1. admin_set_matchable：管理员可切换任意用户的「可被匹配」开关；
-- 2. admin_stats：补充国际服（channel_intl / matchable_intl）统计。
-- 在 Supabase SQL Editor 中整体执行即可（可重复执行）。
-- =====================================================================

-- 1. 管理员切换「可被匹配」开关
create or replace function public.admin_set_matchable(p_admin_code text, p_player_id uuid, p_matchable boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.admin_check_code(p_admin_code);
  update public.players
  set matchable = p_matchable, last_updated_at = now()
  where player_id = p_player_id;
  return jsonb_build_object('player_id', p_player_id, 'matchable', p_matchable);
end;
$$;

-- 2. admin_stats 补充国际服统计
create or replace function public.admin_stats(p_admin_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_players int; v_clans int; v_exchanges int; v_banned int;
  v_wechat int; v_qq int; v_intl int;
  v_wechat_matchable int; v_qq_matchable int; v_intl_matchable int;
begin
  perform public.admin_check_code(p_admin_code);
  select count(*) into v_players from public.players;
  select count(*) into v_clans from public.clans;
  select count(*) into v_exchanges from public.exchanges;
  select count(*) into v_banned from public.players where banned;
  select count(*) into v_wechat from public.players where channel = 'wechat';
  select count(*) into v_qq from public.players where channel = 'qq';
  select count(*) into v_intl from public.players where channel = 'intl';
  select count(*) into v_wechat_matchable from public.players where channel = 'wechat' and matchable;
  select count(*) into v_qq_matchable from public.players where channel = 'qq' and matchable;
  select count(*) into v_intl_matchable from public.players where channel = 'intl' and matchable;
  return jsonb_build_object(
    'players', v_players, 'clans', v_clans, 'exchanges', v_exchanges, 'banned', v_banned,
    'channel_wechat', v_wechat, 'channel_qq', v_qq, 'channel_intl', v_intl,
    'matchable_wechat', v_wechat_matchable, 'matchable_qq', v_qq_matchable, 'matchable_intl', v_intl_matchable
  );
end;
$$;