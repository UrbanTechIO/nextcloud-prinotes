<template>
  <div class="prinotes-quill-wrapper">
    <!-- Toolbar (Quill binds by CSS ID) -->
    <div :id="'ql-toolbar-' + uid" class="ql-toolbar-row">
      <span class="ql-formats">
        <select class="ql-header" title="Text style">
          <option value="1">H1</option>
          <option value="2">H2</option>
          <option value="3">H3</option>
          <option selected>P</option>
        </select>
        <select class="ql-prinotes-size" title="Font size">
          <option selected></option>
          <option value="12px">12</option>
          <option value="15px">15</option>
          <option value="18px">18</option>
          <option value="22px">22</option>
          <option value="28px">28</option>
        </select>
      </span>
      <span class="ql-formats">
        <button class="ql-bold" title="Bold" />
        <button class="ql-italic" title="Italic" />
        <button class="ql-underline" title="Underline" />
        <button class="ql-strike" title="Strike" />
      </span>
      <span class="ql-formats">
        <select class="ql-color" title="Text colour" />
        <select class="ql-background" title="Highlight" />
      </span>
      <span class="ql-formats">
        <button class="ql-list" value="ordered" title="Numbered list" />
        <button class="ql-list" value="bullet" title="Bullet list" />
        <button class="ql-list" value="unchecked" title="Checklist" />
      </span>
      <span class="ql-formats">
        <button class="ql-blockquote" title="Quote" />
        <button class="ql-code-block" title="Code" />
        <button class="ql-link" title="Link" />
      </span>
      <span class="ql-formats">
        <button class="ql-clean" title="Clear formatting" />
      </span>
      <span class="ql-formats">
        <button class="ql-image" title="Insert image" @click="onInsertImage" />
        <button class="ql-prinotes-draw" title="Insert drawing" @click="onOpenDrawing">✎</button>
        <button class="ql-prinotes-divider" title="Insert divider" @click="onInsertDivider">—</button>
      </span>
    </div>

    <!-- Quill target -->
    <div :id="'ql-container-' + uid" class="ql-target" />

    <!-- Hidden file input for image picker -->
    <input ref="fileInput" type="file" accept="image/*" style="display:none" @change="onImagePicked" />

    <!-- Drawing overlay -->
    <div v-if="showDrawing" class="drawing-overlay">
      <DrawingCanvas :initial-data="drawingInitialData" @save="onDrawingSave" @close="showDrawing = false" />
    </div>
  </div>
</template>

<script setup>
/**
 * QuillEditor.vue
 * ───────────────
 *  Real Quill 2.x instance for the web side. Reads/writes the same
 *  `quill-1.0` delta shape used by the Android app (flutter_quill).
 *
 *  Data model (unchanged from Android):
 *    {
 *      version: 'quill-1.0',
 *      delta:   [...Quill delta ops...],
 *      images:  { key: { data: 'data:image/...', width, height, rotation } },
 *      strokes: [...]   // reserved for future canvas-drawing use
 *    }
 *
 *  Custom pieces registered with Quill:
 *    - Numeric font-size format matching flutter_quill values
 *      (12 / 15 / 18 / 22 / 28 px), so a size set on either platform
 *      renders on the other.
 *    - ImageBlot   — the delta stores `{image: 'imgN'}` keys; the blot
 *      resolves the key against a live per-instance images map and
 *      renders an <img>. Keeps the delta small and matches the mobile
 *      encoding exactly.
 *    - DividerBlot — `{divider: true}` embed rendered as <hr>.
 *
 *  Legacy formats:
 *    - v2.0 paragraph format is migrated to quill-1.0 on load.
 *    - Anything else (plain text, markdown) falls through as plain lines.
 *
 *  Emits update:modelValue with the JSON string (same shape as before,
 *  so no store/API changes required).
 */
import { ref, onMounted, onBeforeUnmount, watch, nextTick } from 'vue'
import Quill from 'quill'
import 'quill/dist/quill.snow.css'
import DrawingCanvas from './DrawingCanvas.vue'

const props = defineProps({
  modelValue: { type: String, default: '' },
})
const emit = defineEmits(['update:modelValue'])

const uid = Math.random().toString(36).slice(2, 10)
let quill = null
let internalUpdate = false     // set while WE mutate the doc, so text-change doesn't re-emit
let imagesMap = {}             // key -> { data, width, height, rotation }
let imgCounter = 0

const showDrawing = ref(false)
const drawingInitialData = ref(null)
const fileInput = ref(null)

// ── Custom formats / blots ────────────────────────────────────────────────
// Registered once per module load; the flags below prevent double-registration
// on hot-reload / navigation.
if (!Quill.__prinotesRegistered) {
  Quill.__prinotesRegistered = true

  // Numeric px font size — accept exactly the sizes the mobile toolbar uses.
  const SizeStyle = Quill.import('attributors/style/size')
  SizeStyle.whitelist = ['12px', '15px', '18px', '22px', '28px']
  Quill.register(SizeStyle, true)

  // Explicit alignments (right/center/justify) so they round-trip if mobile
  // ever adds them.
  const AlignStyle = Quill.import('attributors/style/align')
  Quill.register(AlignStyle, true)

  // ImageBlot — renders <img> whose src comes from a per-Quill-instance
  // images map. Delta stays as {image: 'imgN'}, matching flutter_quill.
  const BlockEmbed = Quill.import('blots/block/embed')
  class PriNotesImageBlot extends BlockEmbed {
    static create(key) {
      const node = super.create()
      node.setAttribute('data-key', key)
      node.classList.add('prinotes-image-embed')
      // The actual <img> is stamped in by refreshImageDom() — the blot
      // itself keeps only the key so serialize() reads it back cleanly.
      return node
    }
    static value(node) { return node.getAttribute('data-key') }
  }
  PriNotesImageBlot.blotName = 'image'
  PriNotesImageBlot.tagName = 'div'
  Quill.register(PriNotesImageBlot, true)

  // Divider embed
  class PriNotesDividerBlot extends BlockEmbed {
    static create() {
      const node = super.create()
      node.classList.add('prinotes-divider-embed')
      return node
    }
    static value() { return true }
  }
  PriNotesDividerBlot.blotName = 'divider'
  PriNotesDividerBlot.tagName = 'hr'
  Quill.register(PriNotesDividerBlot, true)
}

// ── Content parsing (input) ───────────────────────────────────────────────
function parseIncoming(raw) {
  const out = { delta: [], images: {}, strokes: [] }
  if (!raw) return out
  try {
    const parsed = JSON.parse(raw)
    if (parsed.version === 'quill-1.0') {
      out.delta   = Array.isArray(parsed.delta) ? parsed.delta : []
      out.images  = parsed.images  ?? {}
      out.strokes = parsed.strokes ?? []
      return out
    }
    if (parsed.version === '2.0') return migrateV2(parsed)
    // Legacy v1.0 web-blocks (before Android existed) — best-effort
    if (Array.isArray(parsed.blocks)) return migrateWebBlocks(parsed)
  } catch {
    // Not JSON — treat as plain text
    out.delta = [{ insert: raw + '\n' }]
    return out
  }
  return out
}

function migrateV2(parsed) {
  const ops = []
  for (const p of (parsed.paragraphs ?? [])) {
    const style = p.style || 'normal'
    const text  = p.text || ''
    if (text) ops.push({ insert: text })
    if      (style === 'h1')        ops.push({ insert: '\n', attributes: { header: 1 } })
    else if (style === 'h2')        ops.push({ insert: '\n', attributes: { header: 2 } })
    else if (style === 'h3')        ops.push({ insert: '\n', attributes: { header: 3 } })
    else if (style === 'bullet')    ops.push({ insert: '\n', attributes: { list: 'bullet' } })
    else if (style === 'numbered')  ops.push({ insert: '\n', attributes: { list: 'ordered' } })
    else if (style === 'checklist') ops.push({ insert: '\n', attributes: { list: p.checked ? 'checked' : 'unchecked' } })
    else                            ops.push({ insert: '\n' })
  }
  const images = {}
  let idx = 0
  for (const img of (parsed.images ?? [])) {
    const key = `img_${idx++}`
    images[key] = { data: img.data || '', width: img.width ?? null, height: img.height ?? null, rotation: img.rotation ?? 0 }
    ops.push({ insert: { image: key } })
    ops.push({ insert: '\n' })
  }
  return { delta: ops, images, strokes: parsed.strokes ?? [] }
}

function migrateWebBlocks(parsed) {
  // Very old web-only format (no Android). Best-effort: dump plain text.
  const ops = []
  for (const b of (parsed.blocks ?? [])) {
    if (b.content) {
      const text = b.content.map(s => (s.text ?? s.insert ?? '')).join('')
      if (text) ops.push({ insert: text })
      ops.push({ insert: '\n' })
    } else if (b.items) {
      for (const it of b.items) {
        if (it.text) ops.push({ insert: it.text })
        ops.push({ insert: '\n', attributes: { list: b.type === 'checklist'
          ? (it.checked ? 'checked' : 'unchecked')
          : (b.ordered ? 'ordered' : 'bullet') } })
      }
    } else if (b.type === 'code') {
      const lines = (b.code ?? '').split('\n')
      for (const line of lines) {
        if (line) ops.push({ insert: line })
        ops.push({ insert: '\n', attributes: { 'code-block': true } })
      }
    } else if (b.type === 'divider') {
      ops.push({ insert: { divider: true } })
      ops.push({ insert: '\n' })
    }
  }
  return { delta: ops, images: {}, strokes: [] }
}

// ── Content serialization (output) ────────────────────────────────────────
function serialize() {
  if (!quill) return props.modelValue
  const contents = quill.getContents()
  // Prune image keys no longer referenced in the delta (defensive)
  const referenced = new Set()
  for (const op of contents.ops) {
    if (op.insert && typeof op.insert === 'object' && op.insert.image) {
      referenced.add(op.insert.image)
    }
  }
  const cleanedImages = {}
  for (const [k, v] of Object.entries(imagesMap)) {
    if (referenced.has(k)) cleanedImages[k] = v
  }
  return JSON.stringify({
    version: 'quill-1.0',
    delta:   contents.ops,
    images:  cleanedImages,
    strokes: [],
  })
}

// ── Rendering image embeds ────────────────────────────────────────────────
// The blot only carries the key; we walk the DOM and paint the real <img>
// after every content change.
function refreshImageDom() {
  if (!quill) return
  const nodes = quill.root.querySelectorAll('div.prinotes-image-embed')
  nodes.forEach(node => {
    const key = node.getAttribute('data-key')
    const meta = imagesMap[key]
    if (!meta || !meta.data) {
      node.innerHTML = '<div class="prinotes-image-missing">missing image</div>'
      return
    }
    // Only replace if the img isn't already there for this key (avoid churn)
    if (node.firstElementChild?.tagName === 'IMG' &&
        node.firstElementChild.getAttribute('data-key') === key) return
    const rotationDeg = (meta.rotation || 0) * 180 / Math.PI
    const w = meta.width ? `${meta.width}px` : '100%'
    node.innerHTML =
      `<img src="${escapeAttr(meta.data)}" data-key="${escapeAttr(key)}" ` +
      `style="max-width:100%;width:${w};height:auto;transform:rotate(${rotationDeg}deg);transform-origin:center center;" ` +
      `draggable="false" />`
  })
}
function escapeAttr(s) {
  return String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;')
}

// ── Insert helpers ────────────────────────────────────────────────────────
function onInsertImage() { fileInput.value?.click() }

function onImagePicked(event) {
  const file = event.target.files?.[0]
  event.target.value = ''
  if (!file) return
  const reader = new FileReader()
  reader.onload = e => {
    const key = `img_${Date.now()}_${imgCounter++}`
    imagesMap[key] = { data: e.target.result, width: null, height: null, rotation: 0 }
    const range = quill.getSelection(true)
    quill.insertEmbed(range.index, 'image', key, Quill.sources.USER)
    quill.setSelection(range.index + 1, 0, Quill.sources.SILENT)
    // refreshImageDom happens on the text-change that Quill fires
  }
  reader.readAsDataURL(file)
}

function onInsertDivider() {
  const range = quill.getSelection(true)
  quill.insertEmbed(range.index, 'divider', true, Quill.sources.USER)
  quill.setSelection(range.index + 1, 0, Quill.sources.SILENT)
}

function onOpenDrawing() {
  drawingInitialData.value = null
  showDrawing.value = true
}
function onDrawingSave({ dataUrl }) {
  showDrawing.value = false
  const key = `drawing_${Date.now()}_${imgCounter++}`
  imagesMap[key] = { data: dataUrl, width: null, height: null, rotation: 0 }
  const range = quill.getSelection(true) || { index: quill.getLength() }
  quill.insertEmbed(range.index, 'image', key, Quill.sources.USER)
  quill.setSelection(range.index + 1, 0, Quill.sources.SILENT)
}

// ── Load content into Quill ───────────────────────────────────────────────
function loadIntoQuill(raw) {
  const { delta, images, strokes } = parseIncoming(raw)
  imagesMap = { ...images }
  // Reserve image counter above any existing numeric suffixes to avoid clash
  for (const k of Object.keys(imagesMap)) {
    const m = k.match(/_(\d+)$/)
    if (m) imgCounter = Math.max(imgCounter, parseInt(m[1], 10) + 1)
  }
  internalUpdate = true
  quill.setContents({ ops: delta.length ? delta : [{ insert: '\n' }] }, Quill.sources.SILENT)
  nextTick(() => {
    refreshImageDom()
    internalUpdate = false
  })
  // Strokes are currently untouched (not in scope for v1.1.0 web parity).
  if (strokes && strokes.length) imagesMap._strokes = strokes
}

// ── Mount ─────────────────────────────────────────────────────────────────
onMounted(() => {
  quill = new Quill(`#ql-container-${uid}`, {
    modules: {
      toolbar: `#ql-toolbar-${uid}`,
      history: { delay: 500, maxStack: 200, userOnly: true },
    },
    theme: 'snow',
    placeholder: 'Start writing…',
  })

  loadIntoQuill(props.modelValue)

  quill.on('text-change', () => {
    // Skip our own programmatic writes (setContents on load)
    if (internalUpdate) return
    refreshImageDom()
    emit('update:modelValue', serialize())
  })
})

onBeforeUnmount(() => {
  quill = null
})

// ── React to external modelValue changes (e.g. version restore) ───────────
watch(() => props.modelValue, (val) => {
  if (!quill) return
  // Only re-load if the incoming string is a genuinely different serialization
  // than what we currently hold — otherwise every emit triggers a reload.
  if (val === serialize()) return
  loadIntoQuill(val)
})
</script>

<style lang="scss" scoped>
.prinotes-quill-wrapper {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-height: 0;
}

// The Quill snow toolbar
.ql-toolbar-row {
  border: 1px solid var(--color-border) !important;
  border-radius: 6px 6px 0 0;
  background: var(--color-main-background) !important;
  flex-shrink: 0;
}

// Custom draw & divider buttons — Quill's built-in buttons all use ::before
// for icons; keep ours simple with unicode
:deep(.ql-prinotes-draw),
:deep(.ql-prinotes-divider) {
  font-size: 1rem;
  line-height: 1;
}

.ql-target {
  flex: 1;
  min-height: 0;
  border: 1px solid var(--color-border) !important;
  border-top: none !important;
  border-radius: 0 0 6px 6px;
  background: var(--color-main-background) !important;
  overflow-y: auto;
}

:deep(.ql-container) {
  font-family: inherit;
  font-size: 1rem;
  border: none !important;
}

:deep(.ql-editor) {
  min-height: 300px;
  color: var(--color-main-text);
  line-height: 1.5;
  padding: 20px 24px 80px;

  h1 { font-size: 1.8rem; font-weight: 700; }
  h2 { font-size: 1.4rem; font-weight: 700; }
  h3 { font-size: 1.15rem; font-weight: 700; }

  blockquote {
    border-left: 3px solid var(--color-primary-element);
    padding-left: 14px;
    color: var(--color-text-lighter);
    font-style: italic;
    margin: 8px 0;
  }

  pre.ql-syntax,
  .ql-code-block-container {
    background: var(--color-background-dark, #1e1e2e);
    color: #e4e4e4;
    border-radius: 6px;
    padding: 12px 14px;
    font-family: 'Fira Code', 'Consolas', monospace;
    font-size: 0.9rem;
  }

  // Checklist visual (Quill renders these as <li data-list="checked/unchecked">)
  li[data-list="checked"] > .ql-ui::before,
  li[data-list="unchecked"] > .ql-ui::before {
    cursor: pointer;
  }
}

:deep(.prinotes-image-embed) {
  display: block;
  margin: 12px 0;
  text-align: left;
  img {
    display: inline-block;
    max-width: 100%;
    border-radius: 4px;
  }
}

:deep(.prinotes-image-missing) {
  padding: 12px;
  border: 1px dashed var(--color-border);
  color: var(--color-text-lighter);
  text-align: center;
  font-size: 0.8rem;
  border-radius: 4px;
}

:deep(.prinotes-divider-embed) {
  border: none;
  border-top: 2px solid var(--color-border);
  margin: 16px 0;
}

// The Quill toolbar picker text (H1/H2/H3/P and font-size labels) can look
// tiny in dark theme — bump slightly for readability
:deep(.ql-prinotes-size .ql-picker-label::before),
:deep(.ql-prinotes-size .ql-picker-item::before) {
  content: attr(data-value);
}
:deep(.ql-prinotes-size .ql-picker-label[data-value]::before) {
  content: attr(data-value);
}

// Drawing overlay
.drawing-overlay {
  position: fixed;
  inset: 0;
  z-index: 100;
  background: var(--color-main-background);
}
</style>
