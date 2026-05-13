<template>
  <div class="app-content editor-app">
    <!-- Word-style ribbon toolbar -->
    <div class="editor-toolbar">
      <button class="toolbar-btn back-btn" @click="goBack" title="Back">
        <ArrowLeft :size="18" />
      </button>
      <div class="toolbar-sep" />
      <button class="toolbar-btn" :class="{ active: note?.isPinned }" @click="togglePin" title="Pin">
        <Pin :size="16" /><span>{{ note?.isPinned ? 'Unpin' : 'Pin' }}</span>
      </button>
      <button class="toolbar-btn" @click="toggleArchive" title="Archive">
        <Archive :size="16" /><span>{{ note?.isArchived ? 'Unarchive' : 'Archive' }}</span>
      </button>
      <button class="toolbar-btn" @click="showLock = true" title="Lock">
        <Lock :size="16" /><span>{{ note?.isLocked ? 'Locked' : 'Lock' }}</span>
      </button>
      <div class="toolbar-sep" />
      <button class="toolbar-btn" @click="showShare = true" title="Share">
        <ShareVariant :size="16" /><span>Share</span>
      </button>
      <button class="toolbar-btn" @click="showReminder = true" title="Reminder">
        <Bell :size="16" /><span>Reminder</span>
      </button>
      <div class="toolbar-sep" />
      <button class="toolbar-btn" @click="exportMarkdown" title="Export">
        <FileDocument :size="16" /><span>Export</span>
      </button>
      <button class="toolbar-btn" @click="showVersions = true" title="History">
        <History :size="16" /><span>History</span>
      </button>
      <button class="toolbar-btn" :class="{ active: showColorPicker }" @click="showColorPicker = !showColorPicker" title="Color">
        <Palette :size="16" /><span>Color</span>
      </button>
      <div class="toolbar-spacer" />
      <span class="save-status" :class="saveStatus">{{ saveStatusText }}</span>
      <div class="toolbar-sep" />
      <button class="toolbar-btn danger" @click="deleteNote" title="Move to Trash">
        <Delete :size="16" /><span>Trash</span>
      </button>
    </div>

    <!-- Color picker bar -->
    <div v-if="showColorPicker" class="color-bar">
      <div v-for="color in colorPalette" :key="color"
        class="color-swatch"
        :class="{ selected: noteColor === color }"
        :style="{ background: color }"
        @click="setNoteColor(color)" />
      <div class="color-swatch clear" @click="setNoteColor(null)">✕</div>
    </div>

    <!-- Lock gate overlay -->
    <div v-if="lockedGate" class="lock-gate">
      <div class="lock-gate-card">
        <div class="lock-gate-icon">🔒</div>
        <h3>This note is locked</h3>
        <p>Enter the PIN to view and edit this note.</p>
        <input
          v-model="gatePIN"
          type="password"
          inputmode="numeric"
          maxlength="8"
          placeholder="PIN"
          class="lock-gate-input"
          autofocus
          @keydown.enter="unlockGate"
        />
        <p v-if="gateError" class="lock-gate-error">{{ gateError }}</p>
        <div class="lock-gate-actions">
          <button class="btn" @click="goBack">Cancel</button>
          <button class="btn btn-primary" @click="unlockGate">Unlock</button>
        </div>
      </div>
    </div>

    <!-- Editor -->
    <div v-else class="editor-body" :style="noteBodyStyle">
      <div class="note-page">
        <!-- Title row: title left, notebook+tags right -->
        <div class="title-row">
          <textarea
            v-model="title"
            class="title-input"
            placeholder="Title"
            dir="ltr"
            rows="1"
            @input="onTitleInput"
          />
          <div class="title-meta">
            <select v-model="selectedNotebook" class="nb-select" @change="debouncedSave">
              <option :value="null">No notebook</option>
              <option v-for="nb in store.notebooks" :key="nb.id" :value="nb.id">{{ nb.title }}</option>
            </select>
            <div class="tag-bar">
              <span v-for="tag in noteTags" :key="tag.id" class="tag-chip"
                :style="{ background: tag.color ? tag.color + '30' : undefined }">
                #{{ tag.name }}
                <button class="tag-remove" @click="removeTag(tag.id)">✕</button>
              </span>
              <select class="tag-add" @change="addTagFromSelect($event)">
                <option value="">+ Tag</option>
                <option v-for="tag in availableTags" :key="tag.id" :value="tag.id">{{ tag.name }}</option>
              </select>
            </div>
          </div>
        </div>
        <BlockEditor
          v-if="loaded"
          v-model="content"
          @update:modelValue="debouncedSave"
        />
      </div>
    </div>

    <!-- Dialogs -->
    <LockDialog v-if="showLock" :note="note" @saved="showLock = false" @close="showLock = false" />
    <ReminderDialog v-if="showReminder" :note="note" @close="showReminder = false" />
    <ShareDialog v-if="showShare" :note="note" @close="showShare = false" />
    <VersionHistoryDialog v-if="showVersions" :note-id="noteId" @restore="onVersionRestore" @close="showVersions = false" />
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import PDropdown from '../components/ui/PDropdown.vue'
import BlockEditor from '../components/editor/BlockEditor.vue'
import LockDialog from '../components/LockDialog.vue'
import ReminderDialog from '../components/ReminderDialog.vue'
import ShareDialog from '../components/ShareDialog.vue'
import VersionHistoryDialog from '../components/VersionHistoryDialog.vue'
import ArrowLeft from 'vue-material-design-icons/ArrowLeft.vue'
import Pin from 'vue-material-design-icons/Pin.vue'
import Archive from 'vue-material-design-icons/Archive.vue'
import Lock from 'vue-material-design-icons/Lock.vue'
import Bell from 'vue-material-design-icons/Bell.vue'
import ShareVariant from 'vue-material-design-icons/ShareVariant.vue'
import History from 'vue-material-design-icons/History.vue'
import FileDocument from 'vue-material-design-icons/FileDocument.vue'
import Palette from 'vue-material-design-icons/Palette.vue'
import Delete from 'vue-material-design-icons/Delete.vue'
import BookOpen from 'vue-material-design-icons/BookOpen.vue'
import { useNotesStore } from '../stores/notes.js'

const route = useRoute()
const router = useRouter()
const store = useNotesStore()

const noteId = computed(() => route.params.id ? parseInt(route.params.id) : null)
const note = ref(null)
const title = ref('')
const content = ref('')
const noteTags = ref([])
const noteColor = ref(null)
const selectedNotebook = ref(null)
const saveStatus = ref('saved')
const showColorPicker = ref(false)
const showLock = ref(false)
const showReminder = ref(false)
const showShare = ref(false)
const showVersions = ref(false)
const saveTimer = ref(null)
const loaded = ref(false)
const lockedGate = ref(false)
const gatePIN = ref('')
const gateError = ref('')

const availableTags = computed(() => store.tags.filter(t => !noteTags.value.find(nt => nt.id === t.id)))
const saveStatusText = computed(() => ({ saving: 'Saving...', error: 'Save failed', saved: 'Saved' }[saveStatus.value] ?? 'Saved'))
const noteBodyStyle = computed(() => noteColor.value ? { background: noteColor.value + '20' } : {})
const colorPalette = ['#fef3c7','#fce7f3','#ede9fe','#dbeafe','#d1fae5','#fee2e2','#e0f2fe','#f0fdf4','#fdf4ff','#fff7ed']

onMounted(async () => {
  if (noteId.value) {
    await loadNote(noteId.value)
  } else {
    // New note — start in edit mode
    title.value = ''
    content.value = ''
  }
  loaded.value = true
})

onUnmounted(() => { if (saveTimer.value) clearTimeout(saveTimer.value) })

async function loadNote(id) {
  try {
    note.value = await store.getNote(id)
    title.value = note.value.title
    noteColor.value = note.value.color
    noteTags.value = note.value.tags ?? []
    selectedNotebook.value = note.value.notebookId
    // Pass raw content to BlockEditor — it handles v1.0, v2.0, and Markdown deserialization
    content.value = note.value.content || ''

    // Show lock gate if note is locked
    if (note.value.isLocked) {
      lockedGate.value = true
    }

  } catch (e) { console.error(e) }
}

function onTitleInput(e) {
  const el = e.target
  el.style.height = 'auto'
  el.style.height = el.scrollHeight + 'px'
  debouncedSave()
}

function debouncedSave() {
  saveStatus.value = 'saving'
  if (saveTimer.value) clearTimeout(saveTimer.value)
  saveTimer.value = setTimeout(saveNow, 1500)
}

async function saveNow() {
  saveStatus.value = 'saving'
  const payload = {
    title: title.value,
    content: content.value,
    color: noteColor.value,
    notebookId: selectedNotebook.value,
    tags: noteTags.value.map(t => t.id),
  }
  try {
    if (noteId.value) {
      note.value = await store.updateNote(noteId.value, payload)
    } else {
      note.value = await store.createNote(payload)
      router.replace(`/note/${note.value.id}`)
    }
    saveStatus.value = 'saved'
  } catch { saveStatus.value = 'error' }
}

async function togglePin() {
  if (!noteId.value) return
  await store.updateNote(noteId.value, { isPinned: !note.value?.isPinned })
  note.value = await store.getNote(noteId.value)
}
async function toggleArchive() {
  if (!noteId.value) return
  await store.updateNote(noteId.value, { isArchived: !note.value?.isArchived })
  note.value = await store.getNote(noteId.value)
}
async function deleteNote() {
  if (!noteId.value) return
  await store.trashNote(noteId.value)
  router.push('/')
}
function addTagFromSelect(event) {
  const tagId = parseInt(event.target.value)
  event.target.value = ''
  if (!tagId) return
  const tag = store.tags.find(t => t.id === tagId)
  if (tag && !noteTags.value.find(t => t.id === tagId)) { noteTags.value.push(tag); saveNow() }
}
async function removeTag(tagId) { noteTags.value = noteTags.value.filter(t => t.id !== tagId); await saveNow() }
async function setNoteColor(color) { noteColor.value = color; showColorPicker.value = false; await saveNow() }
async function onVersionRestore(restoredNote) {
  title.value = restoredNote.title
  content.value = restoredNote.content || ''
  showVersions.value = false
}
function exportMarkdown() {
  let text = content.value
  try {
    const parsed = JSON.parse(text)
    const blocks = parsed.paragraphs ?? parsed.blocks ?? []
    text = blocks.map(b => {
      if (b.type === 'heading') return `${'#'.repeat(b.level || 1)} ${(b.content ?? []).map(s => s.text).join('')}`
      if (b.type === 'paragraph') return (b.content ?? []).map(s => s.text).join('')
      if (b.type === 'quote') return `> ${(b.content ?? []).map(s => s.text).join('')}`
      if (b.type === 'code') return `\`\`\`${b.language || ''}\n${b.code || ''}\n\`\`\``
      if (b.type === 'divider') return '---'
      if (b.type === 'list') return (b.items ?? []).map((it, i) => b.ordered ? `${i + 1}. ${it.text}` : `- ${it.text}`).join('\n')
      if (b.type === 'checklist') return (b.items ?? []).map(it => `- [${it.checked ? 'x' : ' '}] ${it.text}`).join('\n')
      if (b.type === 'image' && b.data) return `![${b.caption || 'image'}](${b.data})`
      return ''
    }).filter(Boolean).join('\n\n')
  } catch { /* already plain text */ }
  const blob = new Blob([text], { type: 'text/markdown' })
  const a = document.createElement('a')
  a.href = URL.createObjectURL(blob)
  a.download = (title.value || 'note') + '.md'
  a.click()
  URL.revokeObjectURL(a.href)
}
function goBack() {
  if (saveTimer.value) { clearTimeout(saveTimer.value); saveNow() }
  router.push('/')
}

async function hashPin(p) {
  const data = new TextEncoder().encode(p + ':prinotes-salt')
  const buf = await crypto.subtle.digest('SHA-256', data)
  return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, '0')).join('')
}

async function unlockGate() {
  if (!gatePIN.value || gatePIN.value.length < 4) {
    gateError.value = 'PIN must be at least 4 digits'
    return
  }
  const hash = await hashPin(gatePIN.value)
  if (hash === note.value?.lockPinHash) {
    lockedGate.value = false
    gateError.value = ''
    gatePIN.value = ''
  } else {
    gateError.value = 'Incorrect PIN'
    gatePIN.value = ''
  }
}
</script>

<style lang="scss" scoped>
.editor-app {
  display: flex;
  flex-direction: column;
  height: 100%;
  overflow: hidden;
}

// ── Word-style ribbon toolbar ─────────────────────────────────────────────
.editor-toolbar {
  display: flex;
  align-items: center;
  gap: 2px;
  padding: 4px 8px;
  border-bottom: 1px solid var(--color-border);
  background: var(--color-main-background);
  z-index: 10;
  flex-shrink: 0;
  flex-wrap: wrap;
}

.toolbar-btn {
  display: inline-flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 2px;
  padding: 4px 8px;
  min-width: 44px;
  border: 1px solid transparent;
  border-radius: 4px;
  background: transparent;
  color: var(--color-main-text);
  cursor: pointer;
  font-size: 0.65rem;
  line-height: 1;
  transition: background 0.1s;

  span { font-size: 0.65rem; white-space: nowrap; color: var(--color-text-lighter); }
  &:hover { background: var(--color-background-hover); border-color: var(--color-border); }
  &.active { background: var(--color-primary-element-light, rgba(var(--color-primary-rgb),0.15)); border-color: var(--color-primary-element); }
  &.back-btn { min-width: 32px; font-size: 1rem; }
  &.danger { color: var(--color-error, #e9322d); span { color: var(--color-error, #e9322d); } }
}

.toolbar-sep {
  width: 1px;
  height: 28px;
  background: var(--color-border);
  margin: 0 4px;
  flex-shrink: 0;
}

.toolbar-spacer { flex: 1; }

.save-status {
  font-size: 0.78rem;
  color: var(--color-text-lighter);
  white-space: nowrap;
  padding: 0 6px;
  &.saving { color: var(--color-warning, #e9a825); }
  &.error   { color: var(--color-error, #e9322d); }
  &.saved   { color: var(--color-success, #46ba61); }
}

// ── Color picker ──────────────────────────────────────────────────────────
.color-bar {
  display: flex;
  gap: 8px;
  padding: 8px 16px;
  background: var(--color-background-dark);
  border-bottom: 1px solid var(--color-border);
  flex-shrink: 0;
}

.color-swatch {
  width: 26px; height: 26px; border-radius: 50%; cursor: pointer;
  border: 2px solid transparent; transition: transform 0.1s;
  &:hover { transform: scale(1.2); }
  &.selected { border-color: var(--color-primary-element); }
  &.clear { background: var(--color-border); display: flex; align-items: center; justify-content: center; font-size: 0.78rem; }
}

// ── Scrollable page area ──────────────────────────────────────────────────
.editor-body {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
}

// ── Full-width document page ──────────────────────────────────────────────
.note-page {
  width: 100%;
  padding: 32px 36px 80px;
  display: flex;
  flex-direction: column;
  box-sizing: border-box;
}

// ── Title row: title left, notebook+tags right ────────────────────────────
.title-row {
  display: flex;
  align-items: flex-start;
  gap: 16px;
  margin-bottom: 16px;
}

.title-input {
  flex: 1;
  display: block;
  font-size: 2rem;
  font-weight: 700;
  line-height: 1.25;
  border: none;
  outline: none;
  background: transparent;
  color: var(--color-main-text);
  padding: 0;
  margin: 0;
  resize: none;
  overflow: hidden;
  font-family: inherit;
  direction: ltr !important;
  text-align: left !important;
  unicode-bidi: isolate;
}

// ── Notebook + tags (top-right of title row) ──────────────────────────────
.title-meta {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 6px;
  flex-shrink: 0;
  padding-top: 6px;
}

.nb-select {
  background: rgba(0, 0, 0, 0.78);
  color: #fff;
  border: 1px solid rgba(255, 255, 255, 0.18);
  border-radius: 6px;
  padding: 4px 10px;
  font-size: 0.8rem;
  cursor: pointer;
  outline: none;
  option { background: #1e1e2e; color: #fff; }
}

.tag-bar {
  display: flex;
  align-items: center;
  gap: 4px;
  flex-wrap: wrap;
  justify-content: flex-end;
}

.tag-chip {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 2px 8px;
  border-radius: 999px;
  background: var(--color-border);
  font-size: 0.78rem;
}

.tag-remove {
  background: none; border: none; cursor: pointer; padding: 0; font-size: 0.65rem;
  color: var(--color-text-lighter);
  &:hover { color: var(--color-error); }
}

.tag-add {
  font-size: 0.78rem;
  border: 1px dashed var(--color-border);
  background: transparent;
  color: var(--color-text-lighter);
  cursor: pointer;
  border-radius: 4px;
  padding: 2px 6px;
  outline: none;
}

// ── Lock gate ─────────────────────────────────────────────────────────────
.lock-gate {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--color-main-background);
}

.lock-gate-card {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
  padding: 40px 32px;
  border: 1px solid var(--color-border);
  border-radius: 12px;
  background: var(--color-main-background);
  box-shadow: 0 4px 24px rgba(0,0,0,0.08);
  min-width: 300px;
  max-width: 400px;
  text-align: center;

  h3 { margin: 0; font-size: 1.1rem; font-weight: 600; }
  p  { margin: 0; font-size: 0.88rem; color: var(--color-text-lighter); }
}

.lock-gate-icon { font-size: 2.5rem; }

.lock-gate-input {
  width: 100%;
  padding: 12px;
  border: 1px solid var(--color-border);
  border-radius: 8px;
  font-size: 1.4rem;
  text-align: center;
  letter-spacing: 0.4em;
  background: var(--color-main-background);
  color: var(--color-main-text);
  &:focus { outline: 2px solid var(--color-primary-element); border-color: transparent; }
}

.lock-gate-error {
  color: var(--color-error, #e9322d) !important;
  font-size: 0.82rem !important;
}

.lock-gate-actions {
  display: flex;
  gap: 10px;
  margin-top: 4px;
}
</style>
