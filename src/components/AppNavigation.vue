<template>
  <div class="nav-inner">
    <!-- Search -->
    <div class="nav-search">
      <input
        v-model="store.searchQuery"
        class="p-input"
        type="search"
        placeholder="Search notes..."
        @input="store.fetchNotes()"
      />
    </div>

    <ul class="nav-list">
      <!-- All Notes -->
      <li
        class="nav-item"
        :class="{ active: !store.activeNotebookId && !store.activeTagId && !store.showTrash && !store.showArchived }"
        @click="selectAll"
      >
        <NoteMultiple :size="18" />
        <span>All Notes</span>
        <span class="nav-counter">{{ totalNotes }}</span>
      </li>

      <!-- Archived -->
      <li class="nav-item" :class="{ active: store.showArchived }" @click="selectArchived">
        <Archive :size="18" />
        <span>Archived</span>
      </li>

      <!-- Trash -->
      <li class="nav-item" :class="{ active: store.showTrash }" @click="selectTrash">
        <Delete :size="18" />
        <span>Trash</span>
      </li>
    </ul>

    <div class="nav-spacer" />

    <!-- Notebooks -->
    <div class="nav-section">
      <div class="nav-section-header" @click="notebooksOpen = !notebooksOpen">
        <Notebook :size="16" />
        <span>Notebooks</span>
        <button class="btn btn-icon nav-add-btn" @click.stop="openNewNotebook" title="New notebook">
          <Plus :size="14" />
        </button>
        <ChevronDown :size="14" :class="{ rotated: !notebooksOpen }" class="nav-chevron" />
      </div>
      <ul v-if="notebooksOpen" class="nav-sublist">
        <li
          v-for="nb in store.notebooks"
          :key="nb.id"
          class="nav-item nav-subitem"
          :class="{ active: store.activeNotebookId === nb.id }"
          @click="selectNotebook(nb.id)"
        >
          <div class="color-dot" :style="{ background: nb.color || '#6b7280' }" />
          <span class="flex-1">{{ nb.title }}</span>
          <button class="nav-action-btn" @click.stop="editNotebook(nb)" title="Edit"><Pencil :size="13" /></button>
          <button class="nav-action-btn danger" @click.stop="store.deleteNotebook(nb.id)" title="Delete"><Delete :size="13" /></button>
        </li>
      </ul>
    </div>

    <!-- Tags -->
    <div class="nav-section">
      <div class="nav-section-header" @click="tagsOpen = !tagsOpen">
        <Tag :size="16" />
        <span>Tags</span>
        <button class="btn btn-icon nav-add-btn" @click.stop="openNewTag" title="New tag">
          <Plus :size="14" />
        </button>
        <ChevronDown :size="14" :class="{ rotated: !tagsOpen }" class="nav-chevron" />
      </div>
      <ul v-if="tagsOpen" class="nav-sublist">
        <li
          v-for="tag in store.tags"
          :key="tag.id"
          class="nav-item nav-subitem"
          :class="{ active: store.activeTagId === tag.id }"
          @click="selectTag(tag.id)"
        >
          <div class="color-dot" :style="{ background: tag.color || '#6b7280' }" />
          <span class="flex-1">#{{ tag.name }}</span>
          <button class="nav-action-btn" @click.stop="editTag(tag)" title="Edit"><Pencil :size="13" /></button>
          <button class="nav-action-btn danger" @click.stop="store.deleteTag(tag.id)" title="Delete"><Delete :size="13" /></button>
        </li>
      </ul>
    </div>

    <!-- Settings -->
    <div class="nav-footer">
      <button class="btn nav-settings-btn" @click="$router.push('/settings')">
        <Cog :size="16" /> Settings
      </button>
    </div>
  </div>

  <!-- New Notebook Modal -->
  <PModal v-if="showNewNotebook" title="Notebook" @close="closeNotebook">
    <NotebookForm :notebook="editingNotebook" @saved="onNotebookSaved" @cancel="closeNotebook" />
  </PModal>

  <!-- New Tag Modal -->
  <PModal v-if="showNewTag" title="Tag" @close="closeTag">
    <TagForm :tag="editingTag" @saved="onTagSaved" @cancel="closeTag" />
  </PModal>
</template>

<script setup>
import { ref, computed } from 'vue'
import NoteMultiple from 'vue-material-design-icons/NoteMultiple.vue'
import Archive from 'vue-material-design-icons/Archive.vue'
import Delete from 'vue-material-design-icons/Delete.vue'
import Notebook from 'vue-material-design-icons/Notebook.vue'
import Tag from 'vue-material-design-icons/Tag.vue'
import Plus from 'vue-material-design-icons/Plus.vue'
import Pencil from 'vue-material-design-icons/Pencil.vue'
import ChevronDown from 'vue-material-design-icons/ChevronDown.vue'
import Cog from 'vue-material-design-icons/Cog.vue'
import PModal from './ui/PModal.vue'
import NotebookForm from './NotebookForm.vue'
import TagForm from './TagForm.vue'
import { useNotesStore } from '../stores/notes.js'
import { useRouter } from 'vue-router'

const store = useNotesStore()
const router = useRouter()

const notebooksOpen = ref(true)
const tagsOpen = ref(true)
const showNewNotebook = ref(false)
const showNewTag = ref(false)
const editingNotebook = ref(null)
const editingTag = ref(null)

const totalNotes = computed(() => store.notes.length)

function selectAll() {
  store.activeNotebookId = null; store.activeTagId = null
  store.showTrash = false; store.showArchived = false
  store.fetchNotes(); router.push('/')
}
function selectNotebook(id) {
  store.activeNotebookId = id; store.activeTagId = null
  store.showTrash = false; store.showArchived = false
  store.fetchNotes(); router.push('/')
}
function selectTag(id) {
  store.activeTagId = id; store.activeNotebookId = null
  store.showTrash = false; store.showArchived = false
  store.fetchNotes(); router.push('/')
}
function selectArchived() {
  store.showArchived = true; store.showTrash = false
  store.activeNotebookId = null; store.activeTagId = null
  store.fetchNotes(); router.push('/')
}
function selectTrash() {
  store.showTrash = true; store.showArchived = false
  store.activeNotebookId = null; store.activeTagId = null
  router.push('/trash')
}
function openNewNotebook() { editingNotebook.value = null; showNewNotebook.value = true }
function editNotebook(nb) { editingNotebook.value = nb; showNewNotebook.value = true }
function closeNotebook() { showNewNotebook.value = false; editingNotebook.value = null }
async function onNotebookSaved() { await store.fetchNotebooks(); closeNotebook() }

function openNewTag() { editingTag.value = null; showNewTag.value = true }
function editTag(tag) { editingTag.value = tag; showNewTag.value = true }
function closeTag() { showNewTag.value = false; editingTag.value = null }
async function onTagSaved() { await store.fetchTags(); closeTag() }
</script>

<style lang="scss" scoped>
.nav-inner {
  display: flex;
  flex-direction: column;
  height: 100%;
  overflow-y: auto;
}

.nav-search {
  padding: 12px;
}

.nav-list {
  list-style: none;
  margin: 0;
  padding: 0 8px;
}

.nav-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 10px;
  border-radius: var(--border-radius, 6px);
  cursor: pointer;
  font-size: 0.9rem;
  color: var(--color-main-text);
  transition: background 0.15s;

  &:hover { background: var(--color-background-hover); }
  &.active { background: var(--color-primary-light); font-weight: 600; }
}

.nav-counter {
  margin-left: auto;
  font-size: 0.75rem;
  background: var(--color-border);
  border-radius: 999px;
  padding: 1px 7px;
  color: var(--color-text-lighter);
}

.nav-spacer {
  height: 8px;
}

.nav-section {
  padding: 4px 8px;
}

.nav-section-header {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 6px 10px;
  border-radius: var(--border-radius, 6px);
  cursor: pointer;
  font-size: 0.8rem;
  font-weight: 600;
  color: var(--color-text-lighter);
  text-transform: uppercase;
  letter-spacing: 0.05em;

  &:hover { background: var(--color-background-hover); }
}

.nav-add-btn {
  margin-left: auto;
  padding: 3px !important;
  min-width: 22px;
  height: 22px;
  border-radius: 50%;
}

.nav-chevron {
  transition: transform 0.2s;
  &.rotated { transform: rotate(-90deg); }
}

.nav-sublist {
  list-style: none;
  margin: 0;
  padding: 0;
}

.nav-subitem {
  font-size: 0.88rem;
  padding: 6px 10px 6px 16px;

  .nav-action-btn {
    display: none;
    background: none;
    border: none;
    cursor: pointer;
    padding: 2px 4px;
    color: var(--color-text-lighter);
    border-radius: 4px;
    &:hover { background: var(--color-background-hover); }
    &.danger:hover { color: var(--color-error); }
  }

  &:hover .nav-action-btn { display: flex; }
}

.flex-1 { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

.color-dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  flex-shrink: 0;
}

.nav-footer {
  margin-top: auto;
  padding: 12px;
  border-top: 1px solid var(--color-border);
}

.nav-settings-btn {
  width: 100%;
  justify-content: flex-start;
}
</style>
