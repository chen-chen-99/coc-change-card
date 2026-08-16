-- =====================================================================
-- 迁移 v10：换卡邮件通知（SendGrid + pg_cron 每 30 分钟）
-- ---------------------------------------------------------------------
-- 功能：
--   1. 用户绑定邮箱 + 开关通知 + 选择范围（twoWay 仅双向 / all 双向+单向）；
--   2. 系统每 30 分钟检查一次所有开启通知的用户：
--      当「从没有可交换卡牌 → 出现可交换卡牌」时，发送【一封】邮件；
--      （不会每张卡发一封；重复"有"状态不会重复发送）
--   3. 通过 SendGrid API 发送（pg_net 异步调用）。
-- 配置（执行后还需填写 SendGrid 密钥，见文件末尾注释）。
-- 适用：已执行过 migration_v9_open_account_permission.sql 的数据库。
-- 在 Supabase SQL Editor 中整体执行。
-- =====================================================================

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