-- =====================================================================
-- 迁移 v7：登录渠道（区服）
-- ---------------------------------------------------------------------
-- 背景：游戏分 QQ / 微信两个登录渠道（区服）。
--   同部落 或 同渠道 → 可换卡；既不同部落也不同渠道 → 不可换卡。
-- 变更：
--   1. players 新增 channel 列（wechat 微信区 / qq QQ区），默认 wechat；
--   2. login_player 增加 p_channel 参数：新玩家写入渠道；老玩家登录时
--      可修改渠道（仅影响匹配结果，不影响玩家唯一性判定）。
-- 适用：已执行过 migration_v6_cross_clan_exchange.sql 的数据库。
-- 在 Supabase SQL Editor 中整体执行。
-- =====================================================================

alter table public.players add column if not exists channel text not null default 'wechat';

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

  -- 2) 玩家：优先按玩家标签找，其次按名称找（渠道不参与唯一性判定）
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

  -- 3) 新建玩家并初始化当前活动库存（channel 走列默认值 wechat）
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