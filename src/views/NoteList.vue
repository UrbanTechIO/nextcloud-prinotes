<template>
  <div class="app-content">
    <!-- Toolbar -->
    <div class="prinotes-toolbar">
      <h2>{{ pageTitle }}</h2>
      <div class="toolbar-right">
        <!-- Bulk actions shown when notes are selected -->
        <template v-if="selectedIds.size > 0">
          <span class="selection-count">{{ selectedIds.size }} selected</span>
          <button class="btn btn-sm" @click="selectAll" title="Select all">All</button>
          <button class="btn btn-sm" @click="clearSelection" title="Deselect">None</button>
          <button class="btn btn-sm" @click="bulkArchive">
            <Archive :size="15" /> Archive
          </button>
          <button class="btn btn-sm btn-error" @click="bulkTrash">
            <Delete :size="15" /> Trash
          </button>
        </template>
        <template v-else>
          <button class="btn btn-primary" @click="newNote">
            <Plus :size="18" /> New Note
          </button>
        </template>
        <button class="btn btn-icon" @click="toggleView" :title="viewMode === 'grid' ? 'Switch to list' : 'Switch to grid'">
          <ViewGrid v-if="viewMode === 'list'" :size="18" />
          <ViewList v-else :size="18" />
        </button>
      </div>
    </div>

    <!-- Loading -->
    <div v-if="store.loading" class="loading-state">
      <div class="p-spinner" style="width:48px;height:48px" />
    </div>

    <!-- Empty State -->
    <div v-else-if="store.filteredNotes.length === 0" class="empty-state">
      <NoteMultiple :size="64" />
      <h3>No notes yet</h3>
      <p>Create your first note to get started</p>
      <button class="btn btn-primary" @click="newNote">New Note</button>
    </div>

    <!-- Notes Grid/List -->
    <div v-else class="notes-container">
      <template v-if="store.pinnedNotes.length">
        <div class="section-label">Pinned</div>
        <div class="notes-grid" :style="gridStyle">
          <NoteCard
            v-for="note in store.pinnedNotes"
            :key="note.id"
            :note="note"
            :view-mode="viewMode"
            :is-selected="selectedIds.has(note.id)"
            :selection-mode="selectedIds.size > 0"
            @click="handleCardClick(note)"
            @select="toggleSelect(note.id)"
            @pin="togglePin(note)"
            @archive="toggleArchive(note)"
            @delete="confirmDelete(note)"
            @color="setColor(note, $event)"
          />
        </div>
      </template>

      <template v-if="store.unpinnedNotes.length">
        <div v-if="store.pinnedNotes.length" class="section-label">Notes</div>
        <div class="notes-grid" :style="gridStyle">
          <NoteCard
            v-for="note in store.unpinnedNotes"
            :key="note.id"
            :note="note"
            :view-mode="viewMode"
            :is-selected="selectedIds.has(note.id)"
            :selection-mode="selectedIds.size > 0"
            @click="handleCardClick(note)"
            @select="toggleSelect(note.id)"
            @pin="togglePin(note)"
            @archive="toggleArchive(note)"
            @delete="confirmDelete(note)"
            @color="setColor(note, $event)"
          />
        </div>
      </template>
    </div>

    <!-- Delete confirm modal -->
    <PModal v-if="noteToDelete" title="Move to Trash" @close="noteToDelete = null">
      <p>Move "<strong>{{ noteToDelete.title || 'Untitled' }}</strong>" to trash?</p>
      <div class="modal-actions">
        <button class="btn" @click="noteToDelete = null">Cancel</button>
        <button class="btn btn-error" @click="doDelete">Move to Trash</button>
      </div>
    </PModal>

    <!-- Bulk trash confirm modal -->
    <PModal v-if="showBulkDeleteConfirm" title="Move to Trash" @close="showBulkDeleteConfirm = false">
      <p>Move <strong>{{ selectedIds.size }}</strong> note{{ selectedIds.size > 1 ? 's' : '' }} to trash?</p>
      <div class="modal-actions">
        <button class="btn" @click="showBulkDeleteConfirm = false">Cancel</button>
        <button class="btn btn-error" @click="doBulkTrash">Move to Trash</button>
      </div>
    </PModal>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import Plus from 'vue-material-design-icons/Plus.vue'
import ViewGrid from 'vue-material-design-icons/ViewGrid.vue'
import ViewList from 'vue-material-design-icons/ViewList.vue'
import NoteMultiple from 'vue-material-design-icons/NoteMultiple.vue'
import Archive from 'vue-material-design-icons/Archive.vue'
import Delete from 'vue-material-design-icons/Delete.vue'
import PModal from '../components/ui/PModal.vue'
import NoteCard from '../components/NoteCard.vue'
import { useNotesStore } from '../stores/notes.js'

const router = useRouter()
const store  = useNotesStore()

const viewMode            = ref(localStorage.getItem('prinotes_view') || 'grid')
const gridStyle           = computed(() => ({
  gridTemplateColumns: viewMode.value === 'grid' ? 'repeat(auto-fill, minmax(220px, 1fr))' : '1fr',
}))
const noteToDelete        = ref(null)
const showBulkDeleteConfirm = ref(false)
const selectedIds         = ref(new Set())

// ── Page title ────────────────────────────────────────────────────────────────
const pageTitle = computed(() => {
  if (store.showTrash)    return 'Trash'
  if (store.showArchived) return 'Archived'
  if (store.activeTagId) {
    const tag = store.tags.find(t => t.id === store.activeTagId)
    return tag ? `#${tag.name}` : 'Tag'
  }
  if (store.activeNotebookId) {
    const nb = store.notebooks.find(n => n.id === store.activeNotebookId)
    return nb?.title ?? 'Notebook'
  }
  return 'All Notes'
})

// ── Note actions ──────────────────────────────────────────────────────────────
async function newNote() {
  const note = await store.createNote()
  router.push(`/note/${note.id}`)
}

function handleCardClick(note) {
  if (selectedIds.value.size > 0) {
    toggleSelect(note.id)
  } else {
    router.push(`/note/${note.id}`)
  }
}

async function togglePin(note)     { await store.updateNote(note.id, { isPinned: !note.isPinned }) }
async function toggleArchive(note) { await store.updateNote(note.id, { isArchived: !note.isArchived }); store.fetchNotes() }
function confirmDelete(note)       { noteToDelete.value = note }
async function doDelete()          { await store.trashNote(noteToDelete.value.id); noteToDelete.value = null }
async function setColor(note, color) { await store.updateNote(note.id, { color }) }

// ── Multi-select ──────────────────────────────────────────────────────────────
function toggleSelect(id) {
  const next = new Set(selectedIds.value)
  if (next.has(id)) next.delete(id)
  else next.add(id)
  selectedIds.value = next
}

function selectAll() {
  selectedIds.value = new Set(store.filteredNotes.map(n => n.id))
}

function clearSelection() {
  selectedIds.value = new Set()
}

function bulkTrash()   { showBulkDeleteConfirm.value = true }
async function bulkArchive() {
  for (const id of selectedIds.value) {
    await store.updateNote(id, { isArchived: true })
  }
  await store.fetchNotes()
  clearSelection()
}
async function doBulkTrash() {
  for (const id of selectedIds.value) {
    await store.trashNote(id)
  }
  showBulkDeleteConfirm.value = false
  clearSelection()
}

// ── View toggle ───────────────────────────────────────────────────────────────
function toggleView() {
  viewMode.value = viewMode.value === 'grid' ? 'list' : 'grid'
  localStorage.setItem('prinotes_view', viewMode.value)
}
</script>

<style lang="scss" scoped>
.prinotes-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14px 24px;
  border-bottom: 1px solid var(--color-border);
  gap: 8px;
  min-height: 58px;

  h2 { margin: 0; font-size: 1.15rem; font-weight: 600; }
  .toolbar-right { display: flex; align-items: center; gap: 6px; flex-wrap: wrap; }
}

.selection-count {
  font-size: 0.85rem;
  font-weight: 600;
  color: var(--color-primary-element);
  margin-right: 2px;
}

.btn-sm {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 4px 10px;
  font-size: 0.82rem;
  border-radius: 6px;
  border: 1px solid var(--color-border);
  background: var(--color-main-background);
  cursor: pointer;
  color: var(--color-main-text);
  transition: background 0.15s;
  &:hover { background: var(--color-background-hover); }
  &.btn-error { color: var(--color-error, #e9322d); border-color: var(--color-error, #e9322d); }
}

.loading-state,
.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  height: calc(100vh - 120px);
  gap: 16px;
  color: var(--color-text-lighter);
  h3 { font-size: 1.2rem; margin: 0; }
  p  { margin: 0; }
}

.notes-container {
  padding: 16px 24px;
  width: 100%;
  box-sizing: border-box;
}

.section-label {
  font-size: 0.72rem;
  font-weight: 600;
  color: var(--color-text-lighter);
  text-transform: uppercase;
  letter-spacing: 0.06em;
  margin: 16px 0 8px;
}

.notes-grid {
  display: grid;
  gap: 12px;
  width: 100%;
}

.modal-actions {
  display: flex;
  gap: 8px;
  justify-content: flex-end;
  margin-top: 16px;
}
</style>
