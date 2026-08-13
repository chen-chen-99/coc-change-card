-- =====================================================================
-- 迁移 v3：访问码模型调整
-- ---------------------------------------------------------------------
-- 新规则：未设置访问码 → 任何设备都能登录并修改（不再绑定单一设备）；
--         已设置访问码 → 仅主人可改，其他设备需输入访问码才能接管。
--
-- 适用：已执行过 schema.sql v2（60 张卡）的数据库。
-- 在 Supabase SQL Editor 中整体执行。
-- =====================================================================

-- 1) 更新 RLS：player_cards 写入条件放宽（无访问码即可写）
drop policy if exists "player_cards_insert_own" on public.player_cards;
drop policy if exists "player_cards_update_own" on public.player_cards;
drop policy if exists "player_cards_delete_own" on public.player_cards;

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

-- 2) 替换 login_player（开放无访问码玩家的编辑权 + 返回 access_code_set）
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
    insert into public.players (clan_id, player_tag, game_name, owner_user_id)
    values (v_clan_id, nullif(p_player_tag, ''), p_player_name, v_uid)
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
-- 3) 新增 set_access_code RPC
--    未设置访问码 → 任何登录用户都可设置并成为"主人"；
--    已设置访问码 → 仅当前主人可修改或清除。
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