<script setup>
import { ref, onMounted } from 'vue';
import { session } from '../lib/store.js';
import { getMyExchangeRecords, undoExchange } from '../lib/api.js';

const loading = ref(false);
const error = ref('');
const notice = ref('');
const records = ref([]);
const busyId = ref('');

async function load() {
  loading.value = true;
  error.value = '';
  try {
    records.value = await getMyExchangeRecords(session.player.player_id, session.cards.map((c) => c.card_id));
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
}

/** 撤销一笔交换：恢复双方卡牌数量（仅交换双方之一可撤销） */
async function onUndo(rec) {
  const ok = window.confirm(
    `确认撤销这笔交换？\n\n` +
      `你 → ${rec.partnerName}：${rec.iGaveName}\n` +
      `${rec.partnerName} → 你：${rec.iGotName}\n\n` +
      `撤销后双方卡牌数量将恢复原状。`
  );
  if (!ok) return;

  busyId.value = rec.exchange_id;
  notice.value = '';
  error.value = '';
  try {
    const res = await undoExchange(rec.exchange_id);
    for (const row of res.updated || []) {
      if (row.player_id === session.player.player_id) session.inventory[row.card_id] = row.quantity;
    }
    notice.value = '✅ 已撤销该笔交换，数据已恢复。';
    await load();
  } catch (e) {
    error.value = e.message;
  } finally {
    busyId.value = '';
  }
}

onMounted(load);
</script>

<template>
  <section>
    <div class="section-head">
      <h2>换卡记录</h2>
      <button class="btn" :disabled="loading" @click="load">刷新</button>
    </div>

    <div v-if="notice" class="banner success">{{ notice }}</div>
    <div v-if="error" class="banner error">{{ error }}</div>
    <div v-if="loading" class="banner">正在读取记录…</div>

    <template v-else-if="!loading">
      <div v-if="records.length === 0" class="banner">暂无换卡记录。完成一笔交换后，可在这里查看并撤销。</div>

      <div v-for="rec in records" :key="rec.exchange_id" class="rec-item rec-record">
        <div class="rec-partner">
          <span v-if="rec.partnerClan" class="partner-clan">{{ rec.partnerClan }}</span>
          <span class="partner-name">{{ rec.partnerName }}</span>
          <span v-if="rec.partnerTag" class="partner-tag">{{ rec.partnerTag }}</span>
        </div>

        <div class="rec-flow">
          <div class="flow-line">你 → {{ rec.partnerName }}：{{ rec.iGaveName }}</div>
          <div class="flow-line">{{ rec.partnerName }} → 你：{{ rec.iGotName }}</div>
        </div>

        <div class="rec-record-foot">
          <span class="rec-meta">时间：{{ new Date(rec.created_at).toLocaleString('zh-CN') }}</span>
          <button
            class="btn btn-undo"
            :disabled="busyId === rec.exchange_id"
            @click="onUndo(rec)"
          >{{ busyId === rec.exchange_id ? '撤销中…' : '↩️ 撤销' }}</button>
        </div>
      </div>
    </template>
  </section>
</template>