<template>
  <div class="notebook-form">
    <div class="form-field">
      <label>Title</label>
      <input v-model="form.title" class="p-input" placeholder="Notebook name" />
    </div>
    <div class="form-field">
      <label>Description</label>
      <input v-model="form.description" class="p-input" placeholder="Optional description" />
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
      <button class="btn btn-primary" @click="save">{{ notebook ? 'Update' : 'Create' }}</button>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useNotesStore } from '../stores/notes.js'

const props = defineProps({ notebook: { type: Object, default: null } })
const emit = defineEmits(['saved', 'cancel'])
const store = useNotesStore()

const colors = ['#ef4444','#f97316','#eab308','#22c55e','#3b82f6','#8b5cf6','#ec4899','#6b7280']

const form = ref({
  title: props.notebook?.title ?? '',
  description: props.notebook?.description ?? '',
  color: props.notebook?.color ?? null,
})

async function save() {
  if (props.notebook) await store.updateNotebook(props.notebook.id, form.value)
  else await store.createNotebook(form.value)
  emit('saved')
}
</script>

<style lang="scss" scoped>
.notebook-form { display: flex; flex-direction: column; gap: 12px; min-width: 300px; }
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
