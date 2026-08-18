<script setup>
import { ref, onMounted } from 'vue';
import { session } from '../lib/store.js';
import { getClanTradingData, executeExchange, getMyExchangeCount } from '../lib/api.js';
import ExchangeRecordsModal from '../components/ExchangeRecordsModal.vue';
import { buildRecommendations, groupByNeededCard } from '../lib/matching.js';
import { categoryLabel } from '../lib/categories.js';

const base = import.meta.env.BASE_URL;
const cardThumbSrc = (card) => base + (card.image_url || '').replace(/^\//, '');

const loading = ref(false);
const error = ref('');
const notice = ref('');
const busyKey = ref('');
const groups = ref([]);
const myMissingCount = ref(0);
const mySpareCount = ref(0);
const otherMemberCount = ref(0);
const myExchangeCount = ref(0);
const showRecords = ref(false);
/** 匹配范围：'clan' 仅同部落 | 'channel' 同渠道（区服）；默认同渠道（同部落人数较少） */
const scope = ref('channel');
/** 单向交换中，我选择给出的多余卡（key -> card_id） */
const selectedGive = ref({});

const cardIds = () => session.cards.map((c) => c.card_id);

/** 每个推荐条目的唯一标识，用于按钮忙碌态 / 选择记忆 */
const swapKeyOf = (rec) =>
  rec.type === 'twoWay'
    ? `${rec.partner.playerId}:${rec.iGive.card_id}:${rec.iGet.card_id}`
    : `oneway:${rec.partner.playerId}:${rec.iGet.card_id}`;

async function load() {
  loading.value = true;
  error.value = '';
  try {
    const { players, inventory } = await getClanTradingData(
      session.player.clan_id,
      cardIds(),
      scope.value,
      session.player.channel ?? 'wechat'
    );
    const me = players.find((p) => p.player_id === session.player.player_id);
    if (!me) throw new Error('未找到当前玩家数据');

    const recs = buildRecommendations({ me, clanMembers: players, cards: session.cards, inventory });
    groups.value = groupByNeededCard(recs);

    // 单向交换默认选第一张多余卡
    for (const g of groups.value) {
      for (const rec of g.items) {
        if (rec.type === 'oneWay') {
          const key = swapKeyOf(rec);
          if (!selectedGive.value[key] && rec.mySpareOptions?.length) {
            selectedGive.value[key] = rec.mySpareOptions[0].card_id;
          }
        }
      }
    }

    const myRows = inventory.filter((r) => r.player_id === me.player_id);
    const keep = me.keep_base ?? 1;
    let missing = 0;
    let spare = 0;
    for (const c of session.cards) {
      const q = myRows.find((r) => r.card_id === c.card_id)?.quantity ?? 0;
      if (q === 0) missing += 1;
      spare += Math.max(0, q - keep);
    }
    myMissingCount.value = missing;
    mySpareCount.value = spare;
    otherMemberCount.value = players.filter((p) => p.player_id !== me.player_id).length;
    myExchangeCount.value = await getMyExchangeCount(session.player.player_id);
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
}

function setScope(s) {
  if (scope.value === s) return;
  scope.value = s;
  notice.value = '';
  load();
}

/** 弹窗内撤销后：刷新推荐数据与个人换卡次数 */
function onRecordsChanged() {
  load();
}

/**
 * 一键交换：双方在游戏中完成交换后，任一方点击即原子同步双方数据。
 * 双向：按推荐给出的卡；单向：按用户下拉选择的同种类多余卡。
 */
async function onSwap(rec) {
  if (!session.activity) {
    error.value = '暂无活动数据，无法交换';
    return;
  }

  let giveCardId = rec.iGive?.card_id;
  if (rec.type === 'oneWay') {
    giveCardId = selectedGive.value[swapKeyOf(rec)];
    if (!giveCardId) {
      error.value = '请先选择你要给出的多余卡';
      return;
    }
  }
  const giveName =
    rec.type === 'twoWay' ? rec.iGive.name : session.cards.find((c) => c.card_id === giveCardId)?.name ?? '';

  const ok = window.confirm(
    `确认已在游戏中完成这组交换？\n\n` +
      `你 → ${rec.partner.gameName}：${giveName}\n` +
      `${rec.partner.gameName} → 你：${rec.iGet.name}\n\n` +
      `点击后将自动同步双方卡牌数据。`
  );
  if (!ok) return;

  busyKey.value = swapKeyOf(rec);
  notice.value = '';
  error.value = '';
  try {
    const res = await executeExchange({
      activityId: session.activity.activity_id,
      playerA: session.player.player_id,
      playerB: rec.partner.playerId,
      cardFromA: giveCardId,
      cardFromB: rec.iGet.card_id,
    });
    if (res.status === 'already_done') {
      notice.value = '该交换已完成（可能对方已同步），已为你刷新最新数据。';
    } else {
      for (const row of res.updated || []) {
        if (row.player_id === session.player.player_id) session.inventory[row.card_id] = row.quantity;
      }
      notice.value = `✅ 交换已同步：你给出 ${giveName}，获得 ${rec.iGet.name}。`;
    }
    await load();
  } catch (e) {
    error.value = e.message;
  } finally {
    busyKey.value = '';
  }
}

onMounted(load);
</script>

<template>
  <section>
    <div class="section-head">
      <h2>换卡推荐</h2>
      <div class="head-actions">
        <button class="btn btn-records" @click="showRecords = true">📋 我的换卡记录（{{ myExchangeCount }}）</button>
        <button class="btn" :disabled="loading" @click="load">刷新</button>
      </div>
    </div>

    <div class="scope-row">
      <span class="scope-label">匹配范围</span>
      <div class="scope-seg">
        <button
          :class="['scope-btn', { active: scope === 'clan' }]"
          @click="setScope('clan')"
        >🏠 仅同部落</button>
        <button
          :class="['scope-btn', { active: scope === 'channel' }]"
          @click="setScope('channel')"
        >🔗 同渠道</button>
      </div>
      <span v-if="scope === 'channel'" class="scope-hint">同渠道内可跨部落匹配</span>
    </div>

    <div class="banner rule-hint">
      📌 只推荐<b>可交换</b>组合：<b>双向互补</b> 或 <b>单方交换</b>（需<b>同种类</b>卡）。
    </div>

    <div v-if="notice" class="banner success">{{ notice }}</div>

    <div class="stats-row">
      <div class="stat"><span class="stat-num">{{ myMissingCount }}</span> 张缺少</div>
      <div class="stat"><span class="stat-num">{{ mySpareCount }}</span> 张可提供</div>
      <div class="stat">
        <span class="stat-num">{{ otherMemberCount }}</span>
        {{ scope === 'channel' ? '位同渠道玩家' : '位成员' }}
      </div>
    </div>

    <div v-if="loading" class="banner">正在计算匹配…</div>
    <div v-if="error" class="banner error">{{ error }}</div>

    <template v-else-if="!loading">
      <div v-if="myMissingCount === 0" class="banner success">🎉 你已经集齐全部卡牌，无需换卡！</div>

      <div v-else-if="groups.length === 0" class="banner">
        暂无可交换的换卡对象。等待更多玩家录入卡牌数据后刷新查看。
      </div>

      <div v-for="g in groups" :key="g.card.card_id" class="rec-group">
        <div class="rec-group-title">
          <img
            v-if="g.card.image_url"
            class="rec-card-thumb"
            :src="cardThumbSrc(g.card)"
            :alt="g.card.name"
          />
          <span>{{ g.card.name }}</span>
          <span class="rec-category">{{ categoryLabel(g.card.category) }}</span>
          <span class="rec-group-count">{{ g.items.length }} 个匹配</span>
        </div>

        <div v-for="(rec, idx) in g.items" :key="idx" class="rec-item" :class="rec.type">
          <div class="rec-partner">
            <span v-if="scope === 'channel' && rec.partner.clanName" class="partner-clan">{{ rec.partner.clanName }}</span>
            <span class="partner-name">{{ rec.partner.gameName }}</span>
            <span v-if="rec.partner.playerTag" class="partner-tag">{{ rec.partner.playerTag }}</span>
            <span class="partner-spare">拥有：{{ g.card.name }} × {{ rec.partner.spareQuantity }}</span>
          </div>

          <template v-if="rec.type === 'twoWay'">
            <div class="rec-flow">
              <div class="flow-line">你 → {{ rec.partner.gameName }}：{{ rec.iGive.name }}</div>
              <div class="flow-line">{{ rec.partner.gameName }} → 你：{{ rec.iGet.name }}</div>
            </div>
            <div class="rec-badge twoWay">★★★★★ 双向交换</div>
          </template>

          <template v-else>
            <div class="rec-flow">
              <div class="flow-line">{{ rec.partner.gameName }} → 你：{{ rec.iGet.name }}</div>
            </div>
            <div class="rec-badge oneWay">🔁 单方交换</div>
            <div class="rec-hint">💡 任选一张你多余的<b>同种类</b>卡即可交换</div>
            <div class="rec-give-pick">
              <span class="give-pick-label">你给（任选一张同种类多余卡）：</span>
              <select v-model="selectedGive[swapKeyOf(rec)]" class="give-pick-select">
                <option v-for="opt in rec.mySpareOptions" :key="opt.card_id" :value="opt.card_id">
                  {{ opt.name }} × {{ opt.spare }}
                </option>
              </select>
            </div>
          </template>

          <div class="rec-swap">
            <button
              class="btn btn-swap"
              :disabled="busyKey === swapKeyOf(rec)"
              @click="onSwap(rec)"
            >{{ busyKey === swapKeyOf(rec) ? '同步中…' : '✅ 交换完成，同步数据' }}</button>
          </div>

          <div v-if="rec.partner.lastUpdatedAt" class="rec-meta">
            数据更新：{{ new Date(rec.partner.lastUpdatedAt).toLocaleString('zh-CN') }}
          </div>
        </div>
      </div>
    </template>
    <ExchangeRecordsModal
      v-if="showRecords"
      @close="showRecords = false"
      @changed="onRecordsChanged"
    />
  </section>
</template>