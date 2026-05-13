<template>
  <Teleport to="body">
    <div class="p-modal-overlay" @mousedown.self="$emit('close')">
      <div class="p-modal" :class="size">
        <div class="p-modal-header">
          <span class="p-modal-title">{{ title }}</span>
          <button class="p-modal-close" @click="$emit('close')">✕</button>
        </div>
        <div class="p-modal-body">
          <slot />
        </div>
      </div>
    </div>
  </Teleport>
</template>

<script setup>
defineProps({
  title: { type: String, default: '' },
  size: { type: String, default: 'normal' },
})
defineEmits(['close'])
</script>

<style lang="scss">
.p-modal-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.5);
  z-index: 10000;
  display: flex;
  align-items: center;
  justify-content: center;
}

.p-modal {
  background: var(--color-main-background);
  border-radius: var(--border-radius-large, 8px);
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.25);
  min-width: 320px;
  max-width: 90vw;
  max-height: 90vh;
  display: flex;
  flex-direction: column;

  &.large { min-width: 640px; }
  &.small { min-width: 280px; }
}

.p-modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 16px 20px;
  border-bottom: 1px solid var(--color-border);
}

.p-modal-title {
  font-weight: 600;
  font-size: 1rem;
}

.p-modal-close {
  background: none;
  border: none;
  cursor: pointer;
  color: var(--color-text-lighter);
  font-size: 1rem;
  padding: 4px 8px;
  border-radius: var(--border-radius);
  &:hover { background: var(--color-background-hover); }
}

.p-modal-body {
  padding: 16px 20px;
  overflow-y: auto;
}
</style>
