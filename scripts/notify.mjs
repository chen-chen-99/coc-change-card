#!/usr/bin/env node
/**
 * 换卡邮件通知脚本（GitHub Actions 每 30 分钟定时运行，替代 SendGrid + pg_cron）
 *
 * 思路：用你自己的 QQ 邮箱 / 163 邮箱（免费）通过 SMTP 发信，
 *       无需域名、无需注册任何第三方邮件服务商。
 *       状态（last_has）保存在 Supabase notification_settings 表：
 *       仅当「从没有可交换卡牌 → 出现可交换卡牌」时，给该用户发【一封】邮件；
 *       邮箱变更后状态自动重置，可再次触发通知。
 *
 * 所需环境变量（在 GitHub 仓库 Settings → Secrets 中配置）：
 *   SUPABASE_URL              = 项目 URL（可复用 VITE_SUPABASE_URL）
 *   SUPABASE_SERVICE_ROLE_KEY = 服务角色密钥（Project Settings → API）
 *   SMTP_HOST                 = smtp.qq.com 或 smtp.163.com
 *   SMTP_PORT                 = 465（默认，SSL）
 *   SMTP_USER                 = 你的邮箱地址（如 xxx@qq.com）
 *   SMTP_PASS                 = 邮箱 SMTP 授权码（不是登录密码！）
 *   SMTP_FROM                 = 发件人地址（一般与 SMTP_USER 相同，可省略）
 */
import { createClient } from '@supabase/supabase-js';
import nodemailer from 'nodemailer';
import { buildRecommendations } from '../src/lib/matching.js';

const APP_URL = process.env.APP_URL || 'https://chen-chen-99.github.io/coc-change-card/';

const required = ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'SMTP_HOST', 'SMTP_USER', 'SMTP_PASS'];
const missing = required.filter((k) => !process.env[k]);
if (missing.length > 0) {
  console.error(`[notify] 缺少环境变量: ${missing.join(', ')}`);
  process.exit(1);
}

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

/** 分页拉取（PostgREST 单次最多 1000 行） */
async function fetchAll(buildQuery, pageSize = 1000) {
  const rows = [];
  let from = 0;
  for (;;) {
    const { data, error } = await buildQuery(from, pageSize);
    if (error) throw error;
    const batch = data || [];
    rows.push(...batch);
    if (batch.length < pageSize) break;
    from += pageSize;
  }
  return rows;
}

const log = (s) => console.log(`[notify] ${s}`);

async function main() {
  // 1. 拉取基础数据：卡牌 + 玩家 + 库存 + 通知设置
  const cards = await fetchAll((from, size) =>
    supabase.from('cards').select('card_id, name, category').order('card_id').range(from, from + size - 1));
  const players = await fetchAll((from, size) =>
    supabase.from('players').select('player_id, game_name, player_tag, keep_base, clan_id, channel, matchable, last_updated_at')
      .order('player_id').range(from, from + size - 1));
  const inventory = await fetchAll((from, size) =>
    supabase.from('player_cards').select('player_id, card_id, quantity')
      .order('player_id').order('card_id').range(from, from + size - 1));
  const settings = await fetchAll((from, size) =>
    supabase.from('notification_settings').select('player_id, email, enabled, scope, last_has')
      .order('player_id').range(from, from + size - 1));

  log(`数据: 卡牌 ${cards.length}, 玩家 ${players.length}, 库存 ${inventory.length}, 通知设置 ${settings.length}`);

  const enabled = settings.filter((s) => s.enabled && s.email && String(s.email).trim());
  if (enabled.length === 0) {
    log('没有开启通知的用户，结束');
    return;
  }

  const playerById = new Map(players.map((p) => [p.player_id, p]));

  const smtpPort = Number(process.env.SMTP_PORT || 465);
  const transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port: smtpPort,
    secure: smtpPort === 465,
    auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
  });
  const from = process.env.SMTP_FROM || process.env.SMTP_USER;

  let sent = 0;
  let failed = 0;
  const updates = [];
  const logs = [];

  for (const ns of enabled) {
    const me = playerById.get(ns.player_id);
    if (!me) {
      log(`跳过: 玩家不存在 ${ns.player_id}`);
      continue;
    }
    // 匹配范围 = 同渠道（区服）或 同部落，与换卡推荐页一致
    const members = players.filter(
      (p) => p.player_id !== ns.player_id && p.matchable !== false && (p.channel === me.channel || p.clan_id === me.clan_id)
    );
    const recs = buildRecommendations({ me, clanMembers: members, cards, inventory });
    const hasTwo = recs.some((r) => r.type === 'twoWay');
    const hasOne = recs.some((r) => r.type === 'oneWay');
    const hasMatch = ns.scope === 'twoWay' ? hasTwo : hasTwo || hasOne;

    const twoCount = new Set(recs.filter((r) => r.type === 'twoWay').map((r) => r.cardINeed.card_id)).size;
    const oneCount = new Set(recs.filter((r) => r.type === 'oneWay').map((r) => r.cardINeed.card_id)).size;

    if (hasMatch && !ns.last_has) {
      // 「从无到有」→ 发一封邮件
      const subject = '【卡牌冲突】你有可交换的卡牌了！';
      const lines = [`你当前有${ns.scope === 'twoWay' ? '可双向交换' : '可交换'}的卡牌：`];
      if (hasTwo) lines.push(`🔁 可双向交换：${twoCount} 种`);
      if (ns.scope !== 'twoWay' && hasOne) lines.push(`🔂 可单向交换：${oneCount} 种`);
      lines.push('');
      lines.push(`请登录系统查看具体内容：${APP_URL}`);
      const text = lines.join('\n');

      try {
        await transporter.sendMail({ from, to: ns.email, subject, text });
        sent += 1;
        updates.push({ player_id: ns.player_id, last_has: true, last_checked_at: new Date().toISOString() });
        logs.push({ player_id: ns.player_id, to_email: ns.email, subject, body: text });
        log(`已发送 → ${ns.email}（${ns.scope}）`);
      } catch (e) {
        failed += 1;
        // 发送失败不更新 last_has，下次运行会自动重试
        console.error(`[notify] 发送失败 → ${ns.email}: ${e.message}`);
      }
    } else if (!!ns.last_has !== hasMatch) {
      // 「有 → 无」或状态变化，仅写状态不发邮件
      updates.push({ player_id: ns.player_id, last_has: hasMatch, last_checked_at: new Date().toISOString() });
    }
  }

  // 写回状态
  for (const u of updates) {
    const { error } = await supabase
      .from('notification_settings')
      .update({ last_has: u.last_has, last_checked_at: u.last_checked_at })
      .eq('player_id', u.player_id);
    if (error) console.error(`[notify] 更新状态失败 ${u.player_id}: ${error.message}`);
  }
  // 记录发送日志（备查）
  if (logs.length > 0) {
    const { error } = await supabase.from('email_queue').insert(logs);
    if (error) console.error(`[notify] 写入发送日志失败: ${error.message}`);
  }

  log(`完成: 新发送 ${sent} 封, 失败 ${failed} 封`);
  if (failed > 0) process.exitCode = 1;
}

main().catch((e) => {
  console.error('[notify] 运行失败:', e);
  process.exit(1);
});