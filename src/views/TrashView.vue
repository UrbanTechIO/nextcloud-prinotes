<template>
  <div class="app-content">
    <div class="prinotes-toolbar">
      <h2>Trash</h2>
      <button class="btn btn-error" @click="emptyTrash" :disabled="!store.notes.length">
        Empty Trash
      </button>
    </div>
    <div v-if="!store.notes.length" class="empty-state">
      <Delete :size="64" />
      <p>Trash is empty</p>
    </div>
    <div v-else class="trash-list">
      <div v-for="note in store.notes" :key="note.id" class="trash-item">
        <div class="trash-info">
          <span class="trash-title">{{ note.title || 'Untitled' }}</span>
          <span class="trash-date">Deleted {{ formatDate(note.trashedAt) }}</span>
        </div>
        <div class="trash-actions">
          <button class="btn" @click="restore(note)">Restore</button>
          <button class="btn btn-error" @click="permanentDelete(note)">Delete permanently</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { onMounted } from 'vue'
import Delete from 'vue-material-design-icons/Delete.vue'
import { useNotesStore } from '../stores/notes.js'

const store = useNotesStore()

onMounted(() => { store.showTrash = true; store.fetchNotes() })

async function restore(note) { await store.restoreNote(note.id) }
async function permanentDelete(note) {
  if (confirm('Permanently delete this note? This cannot be undone.'))
    await store.deleteNotePermanently(note.id)
}
async function emptyTrash() {
  if (!confirm('Permanently delete all notes in trash?')) return
  for (const note of [...store.notes]) await store.deleteNotePermanently(note.id)
}
function formatDate(ts) { return ts ? new Date(ts * 1000).toLocaleDateString() : '' }
</script>

<style lang="scss" scoped>
.prinotes-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 16px 24px;
  border-bottom: 1px solid var(--color-border);
  h2 { margin: 0; font-size: 1.2rem; font-weight: 600; }
}

.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  height: calc(100vh - 120px);
  gap: 12px;
  color: var(--color-text-lighter);
}

.trash-list { padding: 16px 24px; }

.trash-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 16px;
  border: 1px solid var(--color-border);
  border-radius: var(--border-radius, 6px);
  margin-bottom: 8px;
}

.trash-info { display: flex; flex-direction: column; gap: 4px; }
.trash-title { font-weight: 600; font-size: 0.95rem; }
.trash-date { font-size: 0.78rem; color: var(--color-text-lighter); }
.trash-actions { display: flex; gap: 8px; }
</style>
