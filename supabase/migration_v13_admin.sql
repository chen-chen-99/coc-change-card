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