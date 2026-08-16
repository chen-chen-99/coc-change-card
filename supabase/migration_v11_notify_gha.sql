-- =====================================================================
-- 迁移 v11：邮件通知改为「GitHub Actions 定时任务 + SMTP(QQ/163 免费邮箱)」
-- ---------------------------------------------------------------------
-- 背景：原 v10 用 SendGrid 发信（需注册 Twilio/SendGrid、创建 API Key、
--       发件人验证，且 app.sendgrid.com 访问不便），改为更简单的方式：
--   1. 每 30 分钟由 GitHub Actions 运行 scripts/notify.mjs（无需服务器）；
--   2. 用你自己的 QQ 邮箱 / 163 邮箱 SMTP 免费发信（无需域名、无需付费）；
--   3. 状态（last_has）继续存在 notification_settings 表。
-- 本迁移：建表/建 RPC（若 v10 未执行则一并创建）、停用旧的 pg_cron 定时任务、
--         删除旧的 notify_check 函数与 SendGrid 配置。
-- 在 Supabase SQL Editor 中整体执行即可（可重复执行）。
-- =====================================================================

create extension if not exists pg_cron;

-- ---------- 1. 通知设置表 ----------
create table if not exists public.notification_settings (
  player_id      uuid primary key references public.players(player_id),
  email          text,
  enabled        boolean not null default false,
  scope          text not null default 'twoWay',  -- twoWay 仅双向 | all 双向+单向
  last_has       boolean not null default false,  -- 上次检查是否有可交换卡牌（"从无到有"才发）
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

-- ---------- 3. 系统配置 ----------
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

-- ---------- 6. 停用旧的 pg_cron 定时任务（v10 的 SendGrid 方案） ----------
do $$
begin
  if exists (select 1 from pg_cron.job where jobname = 'notify-check-30min') then
    perform cron.unschedule('notify-check-30min');
  end if;
end
$$;

-- ---------- 7. 删除旧的通知检查函数（不再使用） ----------
drop function if exists public.notify_check();

-- ---------- 8. 清理旧的 SendGrid 配置 ----------
delete from public.app_config where key in ('sendgrid_api_key', 'sendgrid_from_email');

-- =====================================================================
-- 执行后还需配置（详见 README「邮件通知」章节）：
--   1. 在 GitHub 仓库 Settings → Secrets and variables → Actions 添加：
--      SUPABASE_SERVICE_ROLE_KEY、SMTP_HOST、SMTP_PORT、SMTP_USER、SMTP_PASS、SMTP_FROM
--      （SMTP_PORT/SMTP_FROM 可省略，脚本默认 465 / 与 SMTP_USER 相同）；
--   2. 把 scripts/notify.mjs 和 .github/workflows/notify.yml 推送到 main；
--   3. 在 Actions 页面手动运行一次「Card Exchange Notify」测试。
-- =====================================================================