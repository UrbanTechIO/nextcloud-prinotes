<template>
  <div class="tag-form">
    <div class="form-field">
      <label>Tag name</label>
      <input v-model="form.name" class="p-input" placeholder="e.g. work, personal..." />
    </div>
    <div class="form-row">
      <label>Color</label>
      <div class="color-swatches">
        <div v-for="c in colors" :key="c" class="swatch"
          :class="{ selected: form.color === c }"
          :style="{ background: c }"
          @click="form.color = c" />
        <div class="swatch clear" @click="form.color = null">✕</div>
      </div>
    </div>
    <div class="form-actions">
      <button class="btn" @click="$emit('cancel')">Cancel</button>
      <button class="btn btn-primary" @click="save">{{ tag ? 'Update' : 'Create' }}</button>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useNotesStore } from '../stores/notes.js'

const props = defineProps({ tag: { type: Object, default: null } })
const emit = defineEmits(['saved', 'cancel'])
const store = useNotesStore()

const colors = ['#ef4444','#f97316','#eab308','#22c55e','#3b82f6','#8b5cf6','#ec4899','#6b7280']

const form = ref({
  name: props.tag?.name ?? '',
  color: props.tag?.color ?? null,
})

async function save() {
  if (props.tag) await store.updateTag(props.tag.id, form.value)
  else await store.createTag(form.value)
  emit('saved')
}
</script>

<style lang="scss" scoped>
.tag-form { display: flex; flex-direction: column; gap: 12px; min-width: 280px; }
.form-field { display: flex; flex-direction: column; gap: 4px; label { font-size: 0.88rem; } }
.form-row { display: flex; align-items: center; gap: 12px; label { min-width: 60px; font-size: 0.88rem; } }
.color-swatches { display: flex; gap: 6px; }
.swatch {
  width: 26px; height: 26px; border-radius: 50%; cursor: pointer; border: 2px solid transparent;
  &.selected { border-color: var(--color-main-text); }
  &.clear { background: var(--color-border); display: flex; align-items: center; justify-content: center; font-size: 0.75rem; }
}
.form-actions { display: flex; gap: 8px; justify-content: flex-end; margin-top: 4px; }
</style>
