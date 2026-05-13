<template>
  <div
    class="note-card"
    :class="[viewMode, { pinned: note.isPinned, selected: isSelected, 'has-color': !!note.color, 'selection-mode': selectionMode }]"
    :style="cardStyle"
    @click="handleClick"
  >
    <!-- Selection checkbox -->
    <div class="card-select" @click.stop="$emit('select')">
      <div class="select-circle" :class="{ checked: isSelected }">
        <Check v-if="isSelected" :size="11" />
      </div>
    </div>

    <!-- Selection overlay -->
    <div v-if="isSelected" class="selected-overlay" />

    <!-- ── GRID LAYOUT ─────────────────────────────────────────────── -->
    <template v-if="viewMode === 'grid'">
      <!-- Full-width image at the top of the card -->
      <div v-if="!note.isLocked && previewSrc" class="card-image">
        <img :src="previewSrc" alt="" />
      </div>

      <!-- Card body -->
      <div class="card-body">
        <div class="card-header">
          <h3 class="card-title" :class="{ 'locked-title': note.isLocked }">
            {{ note.isLocked && !note.title ? 'Locked Note' : (note.title || 'Untitled') }}
          </h3>
          <div class="card-header-right" @click.stop>
            <Pin v-if="note.isPinned" :size="13" class="pin-icon" />
            <PDropdown>
              <button class="p-dropdown-item" @click="$emit('pin')">
                <Pin :size="15" /> {{ note.isPinned ? 'Unpin' : 'Pin' }}
              </button>
              <button class="p-dropdown-item" @click="$emit('archive')">
                <Archive :size="15" /> {{ note.isArchived ? 'Unarchive' : 'Archive' }}
              </button>
              <button class="p-dropdown-item" @click.stop="showColorPicker = !showColorPicker">
                <Palette :size="15" /> Color
              </button>
              <button class="p-dropdown-item danger" @click="$emit('delete')">
                <Delete :size="15" /> Move to Trash
              </button>
            </PDropdown>
          </div>
        </div>

        <!-- Preview text — snapshot with fade -->
        <div v-if="!note.isLocked && note.preview" class="card-preview-wrap">
          <p class="card-preview">{{ note.preview }}</p>
        </div>
        <p v-else-if="note.isLocked" class="card-preview locked-hint">🔒 Locked</p>

        <div class="card-spacer" />

        <!-- Tags at the bottom -->
        <div v-if="!note.isLocked && note.tags?.length" class="card-tags">
          <span
            v-for="tag in note.tags.slice(0, 3)"
            :key="tag.id"
            class="tag-chip"
            :style="tagStyle(tag)"
          >#{{ tag.name }}</span>
          <span v-if="note.tags.length > 3" class="tag-more">+{{ note.tags.length - 3 }}</span>
        </div>

        <div class="card-footer">
          <span class="card-date">{{ formatDate(note.updatedAt) }}</span>
          <Lock v-if="note.isLocked" :size="13" class="lock-icon" />
        </div>
      </div>
    </template>

    <!-- ── LIST LAYOUT ─────────────────────────────────────────────── -->
    <template v-else>
      <div class="list-body">
        <!-- Left: text info -->
        <div class="list-text">
          <div class="list-title-row">
            <h3 class="card-title">{{ note.title || 'Untitled' }}</h3>
            <Pin v-if="note.isPinned" :size="13" class="pin-icon" />
            <Lock v-if="note.isLocked" :size="13" class="lock-icon" />
          </div>
          <p v-if="!note.isLocked && note.preview" class="list-preview">{{ note.preview }}</p>
          <div v-if="!note.isLocked && !note.preview && note.hasMedia" class="list-media-hint">
            <Draw :size="12" /><span>Drawing</span>
          </div>
          <div v-if="!note.isLocked && note.tags?.length" class="card-tags list-tags">
            <span
              v-for="tag in note.tags.slice(0, 3)"
              :key="tag.id"
              class="tag-chip"
              :style="tagStyle(tag)"
            >#{{ tag.name }}</span>
          </div>
        </div>

        <!-- Right: thumbnail + date + actions -->
        <div class="list-right" @click.stop>
          <img v-if="!note.isLocked && previewSrc" :src="previewSrc" class="list-thumb" />
          <span class="card-date">{{ formatDate(note.updatedAt) }}</span>
          <PDropdown>
            <button class="p-dropdown-item" @click="$emit('pin')">
              <Pin :size="15" /> {{ note.isPinned ? 'Unpin' : 'Pin' }}
            </button>
            <button class="p-dropdown-item" @click="$emit('archive')">
              <Archive :size="15" /> {{ note.isArchived ? 'Unarchive' : 'Archive' }}
            </button>
            <button class="p-dropdown-item" @click.stop="showColorPicker = !showColorPicker">
              <Palette :size="15" /> Color
            </button>
            <button class="p-dropdown-item danger" @click="$emit('delete')">
              <Delete :size="15" /> Move to Trash
            </button>
          </PDropdown>
        </div>
      </div>
    </template>

    <!-- Color picker popup -->
    <div v-if="showColorPicker" class="color-picker-popup" @click.stop>
      <div v-for="color in colorPalette" :key="color" class="color-swatch"
        :class="{ selected: note.color === color }"
        :style="{ background: color }"
        @click.stop="pickColor(color)" />
      <div class="color-swatch clear" @click.stop="pickColor(null)">✕</div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, nextTick, watch } from 'vue'
import PDropdown from './ui/PDropdown.vue'
import Pin from 'vue-material-design-icons/Pin.vue'
import Archive from 'vue-material-design-icons/Archive.vue'
import Palette from 'vue-material-design-icons/Palette.vue'
import Delete from 'vue-material-design-icons/Delete.vue'
import Lock from 'vue-material-design-icons/Lock.vue'
import Check from 'vue-material-design-icons/Check.vue'
import ImageMultiple from 'vue-material-design-icons/ImageMultiple.vue'
import Draw from 'vue-material-design-icons/Draw.vue'
import { useNotesStore } from '../stores/notes.js'

const props = defineProps({
  note:          { type: Object,  required: true },
  viewMode:      { type: String,  default: 'grid' },
  isSelected:    { type: Boolean, default: false },
  selectionMode: { type: Boolean, default: false },
})
const emit = defineEmits(['click', 'select', 'pin', 'archive', 'delete', 'color'])

const store = useNotesStore()
const showColorPicker = ref(false)
const strokeCanvas = ref(null)

// ── Color preview from cached content ────────────────────────────────────────
const previewSrc   = ref(null)   // first image data URI
const strokeData   = ref([])     // strokes array for canvas rendering

const hasStrokes  = computed(() => strokeData.value.length > 0)
const showVisual  = computed(() =>
  !!previewSrc.value || hasStrokes.value || props.note.hasMedia
)

function parseContentForPreview(content) {
  if (!content) return
  try {
    const data = JSON.parse(content)
    // quill-1.0: images is a keyed object { img_0: { data, ... } }
    if (data.version === 'quill-1.0') {
      const images = data.images ?? {}
      const first = Object.values(images)[0]
      if (first?.data) previewSrc.value = first.data
      return
    }
    // v2.0 format: images[] array + strokes[]
    if (Array.isArray(data.images) && data.images.length) {
      previewSrc.value = data.images[0].data ?? null
      return
    }
    if (data.strokes?.length) {
      strokeData.value = data.strokes
      return
    }
    // v1.0 blocks
    for (const block of data.blocks ?? []) {
      if ((block.type === 'image' || block.type === 'drawing') && block.data) {
        previewSrc.value = block.data
        return
      }
    }
  } catch {
    // Markdown: grab first embedded image
    const m = content.match(/!\[[^\]]*\]\((data:image\/[^)]{1,2000})\)/)
    if (m) previewSrc.value = m[1]
  }
}

onMounted(() => {
  const cached = store.peekNote(props.note.id)
  if (cached?.content) parseContentForPreview(cached.content)
  if (hasStrokes.value) nextTick(renderStrokes)
})

watch(hasStrokes, (v) => { if (v) nextTick(renderStrokes) })

function renderStrokes() {
  const canvas = strokeCanvas.value
  if (!canvas) return
  const ctx = canvas.getContext('2d')
  const w = canvas.offsetWidth || 240
  const h = canvas.offsetHeight || 130
  canvas.width  = w
  canvas.height = h

  // Background
  const dark = window.matchMedia('(prefers-color-scheme: dark)').matches
  ctx.fillStyle = dark ? '#1e1e2e' : '#f8fafc'
  ctx.fillRect(0, 0, w, h)

  const strokes = strokeData.value.filter(s => !s.eraser)
  if (!strokes.length) return

  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
  for (const s of strokes) {
    for (const pt of (s.pts || [])) {
      if (pt[0] < minX) minX = pt[0]; if (pt[1] < minY) minY = pt[1]
      if (pt[0] > maxX) maxX = pt[0]; if (pt[1] > maxY) maxY = pt[1]
    }
  }
  if (minX === Infinity) return

  const pad = 8
  const scale = Math.min(
    (w - pad * 2) / Math.max(maxX - minX, 1),
    (h - pad * 2) / Math.max(maxY - minY, 1),
  )
  const dx = pad - minX * scale
  const dy = pad - minY * scale

  for (const s of strokes) {
    const pts = s.pts || []
    if (pts.length < 2) continue
    // Mobile color format: "0xFFRRGGBB"
    let color = '#888'
    try {
      const hex = (s.color || '').replace(/^0x/i, '')
      color = '#' + (hex.length === 8 ? hex.slice(2) : hex)
    } catch { /* keep default */ }
    ctx.strokeStyle = color
    ctx.lineWidth   = Math.max(0.5, Math.min(4, (s.width || 2) * scale))
    ctx.lineCap     = 'round'
    ctx.lineJoin    = 'round'
    ctx.beginPath()
    ctx.moveTo(pts[0][0] * scale + dx, pts[0][1] * scale + dy)
    for (let i = 1; i < pts.length; i++) {
      ctx.lineTo(pts[i][0] * scale + dx, pts[i][1] * scale + dy)
    }
    ctx.stroke()
  }
}

// ── Card styling ─────────────────────────────────────────────────────────────
const colorPalette = [
  '#fef3c7', '#fce7f3', '#ede9fe', '#dbeafe', '#d1fae5',
  '#fee2e2', '#e0f2fe', '#f0fdf4', '#fdf4ff', '#fff7ed',
]

function hexToRgba(hex, alpha) {
  const r = parseInt(hex.slice(1, 3), 16)
  const g = parseInt(hex.slice(3, 5), 16)
  const b = parseInt(hex.slice(5, 7), 16)
  return `rgba(${r},${g},${b},${alpha})`
}

const cardStyle = computed(() => {
  const c = props.note.color
  if (!c) return {}
  return {
    background:   hexToRgba(c, 0.12),
    borderColor:  hexToRgba(c, 0.55),
    borderWidth:  '1.5px',
    boxShadow:    `0 4px 16px ${hexToRgba(c, 0.40)}`,
  }
})

function tagStyle(tag) {
  if (!tag.color) return {}
  return {
    background: tag.color + '22',
    color:      tag.color,
  }
}

function formatDate(ts) {
  if (!ts) return ''
  const d    = new Date(ts * 1000)
  const diff = Date.now() - d
  if (diff < 60000)    return 'Just now'
  if (diff < 3600000)  return `${Math.floor(diff / 60000)}m ago`
  if (diff < 86400000) return `${Math.floor(diff / 3600000)}h ago`
  if (diff < 604800000) return d.toLocaleDateString(undefined, { weekday: 'short' })
  return d.toLocaleDateString()
}

function pickColor(color) { emit('color', color); showColorPicker.value = false }

function handleClick() {
  if (props.selectionMode) emit('select')
  else emit('click')
}
</script>

<style lang="scss" scoped>
.note-card {
  position: relative;
  border-radius: 12px;
  border: 1px solid var(--color-border);
  background: var(--color-main-background);
  cursor: pointer;
  transition: box-shadow 0.2s, transform 0.15s;
  display: flex;
  flex-direction: column;

  &:hover {
    box-shadow: 0 6px 20px rgba(0,0,0,.12);
    transform: translateY(-2px);
    .card-select { opacity: 1; }
  }
  &.pinned { border-color: var(--color-primary-element-light, #aad4f5); }
  &.selected { outline: 2px solid var(--color-primary-element); outline-offset: 1px; }
  &.selection-mode .card-select { opacity: 1; }
  &.list { flex-direction: row; }
}

// ── Selection checkbox ────────────────────────────────────────────────────────
.card-select {
  position: absolute;
  top: 8px;
  left: 8px;
  z-index: 10;
  opacity: 0;
  transition: opacity 0.15s;
}

.select-circle {
  width: 20px;
  height: 20px;
  border-radius: 50%;
  border: 2px solid var(--color-border);
  background: var(--color-main-background);
  display: flex;
  align-items: center;
  justify-content: center;
  transition: background 0.15s, border-color 0.15s;
  box-shadow: 0 1px 4px rgba(0,0,0,.2);

  &.checked {
    background: var(--color-primary-element);
    border-color: var(--color-primary-element);
    color: #fff;
  }
}

.selected-overlay {
  position: absolute;
  inset: 0;
  background: rgba(0,120,215,0.10);
  border-radius: 12px;
  pointer-events: none;
  z-index: 5;
}

// ── Full-width image block ────────────────────────────────────────────────────
.card-image {
  width: 100%;
  overflow: hidden;
  border-radius: 11px 11px 0 0;
  flex-shrink: 0;

  img {
    display: block;
    width: 100%;
    max-height: 180px;
    object-fit: cover;
  }
}

// ── Card body ─────────────────────────────────────────────────────────────────
.card-body {
  padding: 10px 12px 12px;
  display: flex;
  flex-direction: column;
  flex: 1;
  min-height: 100px;
  gap: 4px;
}

.card-spacer { flex: 1; }

.card-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 6px;
}

.card-header-right {
  display: flex;
  align-items: center;
  gap: 4px;
  flex-shrink: 0;
}

.card-title {
  font-size: 0.9rem;
  font-weight: 600;
  margin: 0;
  line-height: 1.3;
  overflow: hidden;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  color: var(--color-main-text);

  &.locked-title { color: var(--color-text-lighter); }
}

.card-preview-wrap {
  position: relative;
  overflow: hidden;
  max-height: 78px; // ~4 lines at 0.8rem * 1.45
  -webkit-mask-image: linear-gradient(to bottom, black 30%, transparent 100%);
  mask-image: linear-gradient(to bottom, black 30%, transparent 100%);
}

.card-preview {
  font-size: 0.8rem;
  color: var(--color-text-lighter);
  line-height: 1.45;
  margin: 0;
  white-space: pre-wrap;
  word-break: break-word;

  &.locked-hint {
    font-style: italic;
    white-space: normal;
  }
}

.card-tags {
  display: flex;
  flex-wrap: wrap;
  gap: 3px;
}

.tag-chip {
  font-size: 0.70rem;
  padding: 2px 7px;
  border-radius: 999px;
  background: var(--color-primary-light);
  color: var(--color-primary-element);
  font-weight: 500;
}

.tag-more { font-size: 0.70rem; color: var(--color-text-lighter); padding: 2px 3px; }

.card-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-top: auto;
}

.card-date { font-size: 0.70rem; color: var(--color-text-lighter); }

.pin-icon  { color: var(--color-primary-element); }
.lock-icon { color: #f59e0b; }

// ── List layout ───────────────────────────────────────────────────────────────
.list-body {
  display: flex;
  align-items: center;
  padding: 12px 14px;
  gap: 10px;
  width: 100%;
}

.list-text {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 3px;
}

.list-title-row {
  display: flex;
  align-items: center;
  gap: 5px;
  .card-title { -webkit-line-clamp: 1; }
}

.list-preview {
  font-size: 0.82rem;
  color: var(--color-text-lighter);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  margin: 0;
}

.list-media-hint {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 0.78rem;
  color: var(--color-text-lighter);
}

.list-tags { flex-wrap: nowrap; }

.list-right {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 4px;
  flex-shrink: 0;
}

.list-thumb {
  width: 52px;
  height: 52px;
  object-fit: cover;
  border-radius: 6px;
  border: 1px solid var(--color-border);
}

// ── Color picker popup ────────────────────────────────────────────────────────
.color-picker-popup {
  position: absolute;
  bottom: 8px;
  right: 8px;
  background: var(--color-main-background);
  border: 1px solid var(--color-border);
  border-radius: 8px;
  padding: 8px;
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  max-width: 160px;
  z-index: 200;
  box-shadow: 0 4px 16px rgba(0,0,0,.18);
}

.color-swatch {
  width: 22px; height: 22px; border-radius: 50%; cursor: pointer;
  border: 2px solid transparent; transition: transform 0.1s;
  &:hover { transform: scale(1.2); }
  &.selected { border-color: var(--color-primary-element); }
  &.clear { background: var(--color-border); display: flex; align-items: center; justify-content: center; font-size: 0.72rem; }
}
</style>
