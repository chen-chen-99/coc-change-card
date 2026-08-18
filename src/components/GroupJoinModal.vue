<script setup>
import GroupJoinCard from './GroupJoinCard.vue';

const emit = defineEmits(['close']);
</script>

<template>
  <div class="modal-backdrop" @click.self="emit('close')">
    <div class="modal">
      <div class="modal-head">
        <h3>👋 欢迎使用换卡助手</h3>
        <button class="btn btn-ghost" @click="emit('close')">✕ 关闭</button>
      </div>
      <div class="modal-body">
        <GroupJoinCard />
        <div class="modal-actions">
          <button class="btn btn-primary btn-block" @click="emit('close')">我知道了，开始使用</button>
        </div>
      </div>
    </div>
  </div>
</template>