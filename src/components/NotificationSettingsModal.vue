<script setup>
import { ref } from 'vue';
import { session } from '../lib/store.js';
import { setNotificationSettings } from '../lib/api.js';

const emit = defineEmits(['close', 'saved']);

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const current = session.player?.notify ?? { email: null, enabled: false, scope: 'twoWay' };

const email = ref(current.email || '');
const scope = ref(current.scope === 'all' ? 'all' : 'twoWay');
const saving = ref(false);
const error = ref('');
const notice = ref('');

async function save(enabled) {
  error.value = '';
  notice.value = '';
  if (enabled && !EMAIL_RE.test(email.value.trim())) {
    error.value = '请填写正确的邮箱地址';
    return;
  }
  saving.value = true;
  try {
    const res = await setNotificationSettings(session.player.player_id, {
      email: email.value.trim(),
      enabled,
      scope: scope.value,
    });
    session.player.notify = { email: res.email, enabled: res.enabled, scope: res.scope };
    notice.value = enabled
      ? '✅ 通知已开启：系统每 30 分钟检查一次，出现可交换卡牌时会发送一封邮件。'
      : '通知已关闭。';
    emit('saved');
  } catch (e) {
    error.value = e.message;
  } finally {
    saving.value = false;
  }
}
</script>

<template>
  <div class="modal-backdrop" @click.self="emit('close')">
    <div class="modal">
      <div class="modal-head">
        <h3>🔔 换卡通知</h3>
        <button class="btn btn-ghost" @click="emit('close')">✕ 关闭</button>
      </div>

      <div class="modal-body">
        <p class="field-hint">
          每 30 分钟检查一次，出现可交换卡牌时发送<b>一封</b>邮件提醒。
        </p>

        <div v-if="notice" class="banner success">{{ notice }}</div>
        <div v-if="error" class="banner error">{{ error }}</div>

        <label class="field">
          <span>通知邮箱（开启通知必填）</span>
          <input v-model.trim="email" type="email" placeholder="you@example.com" />
        </label>

        <div class="field">
          <span>通知范围</span>
          <div class="scope-seg">
            <button
              type="button"
              :class="['scope-btn', { active: scope === 'twoWay' }]"
              @click="scope = 'twoWay'"
            >🔁 仅双向交换</button>
            <button
              type="button"
              :class="['scope-btn', { active: scope === 'all' }]"
              @click="scope = 'all'"
            >双向 + 单向</button>
          </div>
          <small class="field-hint">
            {{ scope === 'twoWay' ? '仅双向互补时通知' : '双向、单向都会通知' }}
          </small>
        </div>

        <div class="modal-actions">
          <button
            v-if="!current.enabled"
            class="btn btn-primary"
            :disabled="saving"
            @click="save(true)"
          >{{ saving ? '保存中…' : '开启通知' }}</button>
          <template v-else>
            <button class="btn btn-primary" :disabled="saving" @click="save(true)">
              {{ saving ? '保存中…' : '保存设置' }}
            </button>
            <button class="btn btn-undo" :disabled="saving" @click="save(false)">关闭通知</button>
          </template>
        </div>
      </div>
    </div>
  </div>
</template>