<script setup>
const emit = defineEmits(['close']);
</script>

<template>
  <div class="modal-backdrop">
    <div class="modal">
      <div class="modal-head">
        <h3>🚫 账号已被禁用</h3>
      </div>
      <div class="modal-body">
        <p class="banned-text">你的账号已被管理员禁用，无法继续使用换卡助手。</p>
        <p class="banned-text">
          使用前请先加入对应渠道的群，或联系开发者：<b>QQ 1456734671 · 部落号 #29UL9PRJR</b>。
        </p>
        <div class="modal-actions">
          <button class="btn btn-primary btn-block" @click="emit('close')">退出登录</button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.banned-text { line-height: 1.7; font-size: 14px; margin: 0 0 10px; }
</style>