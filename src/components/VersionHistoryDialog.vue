<template>
  <PModal title="Version History" size="large" @close="$emit('close')">
    <div class="version-content">
      <div v-if="loading" class="loading-center"><div class="p-spinner" /></div>
      <div v-else-if="!versions.length" class="empty">
        <p>No version history yet. Versions are created automatically when you edit.</p>
      </div>
      <template v-else>
        <div class="versions-list">
          <div v-for="v in versions" :key="v.id"
            class="version-item"
            :class="{ active: selectedVersion?.id === v.id }"
            @click="selectVersion(v)">
            <div class="version-meta">
              <span class="version-num">v{{ v.versionNumber }}</span>
              <span class="version-date">{{ formatDate(v.createdAt) }}</span>
            </div>
            <div class="version-title">{{ v.title || 'Untitled' }}</div>
          </div>
        </div>

        <div v-if="selectedVersion" class="version-preview">
          <h4>Preview — v{{ selectedVersion.versionNumber }}</h4>
          <div class="preview-content">
            <h3>{{ selectedVersion.title }}</h3>
            <p>{{ extractPreview(selectedVersion.content) }}</p>
          </div>
          <button class="btn btn-primary" @click="restore">Restore this version</button>
        </div>
      </template>
    </div>
  </PModal>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import PModal from './ui/PModal.vue'
import { useNotesStore } from '../stores/notes.js'

const props = defineProps({ noteId: { type: Number, required: true } })
const emit = defineEmits(['restore', 'close'])

const store = useNotesStore()
const versions = ref([])
const loading = ref(true)
const selectedVersion = ref(null)

onMounted(async () => {
  versions.value = await store.getVersions(props.noteId)
  loading.value = false
})

function selectVersion(v) { selectedVersion.value = v }

async function restore() {
  if (!selectedVersion.value) return
  emit('restore', await store.restoreVersion(props.noteId, selectedVersion.value.id))
}

function formatDate(ts) { return new Date(ts * 1000).toLocaleString() }

function extractPreview(contentJson) {
  try {
    const data = JSON.parse(contentJson)
    for (const block of data.blocks ?? []) {
      if (['paragraph', 'heading', 'quote'].includes(block.type))
        return (block.content ?? []).map(s => s.text || '').join('').substring(0, 200)
    }
  } catch {}
  return '(No preview)'
}
</script>

<style lang="scss" scoped>
.version-content {
  display: flex;
  gap: 16px;
  min-height: 300px;
  min-width: 560px;
}

.loading-center, .empty {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
  color: var(--color-text-lighter);
}

.versions-list {
  width: 200px;
  flex-shrink: 0;
  border-right: 1px solid var(--color-border);
  overflow-y: auto;
  max-height: 400px;
}

.version-item {
  padding: 10px 12px;
  cursor: pointer;
  border-bottom: 1px solid var(--color-border);
  transition: background 0.15s;
  &:hover { background: var(--color-background-hover); }
  &.active { background: var(--color-primary-light); }
}

.version-meta {
  display: flex;
  justify-content: space-between;
  font-size: 0.72rem;
  color: var(--color-text-lighter);
  margin-bottom: 4px;
}

.version-num { font-weight: 600; color: var(--color-primary-element); }

.version-title {
  font-size: 0.85rem;
  font-weight: 500;
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
}

.version-preview {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 12px;
  h4 { font-size: 0.88rem; color: var(--color-text-lighter); font-weight: 600; margin: 0; }
}

.preview-content {
  flex: 1;
  border: 1px solid var(--color-border);
  border-radius: var(--border-radius, 6px);
  padding: 16px;
  overflow-y: auto;
  h3 { font-size: 1.1rem; margin: 0 0 8px; }
  p { font-size: 0.88rem; color: var(--color-text-lighter); margin: 0; }
}
</style>
