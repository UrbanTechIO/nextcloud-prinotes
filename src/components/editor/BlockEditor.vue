<template>
  <div class="block-editor" dir="ltr">
    <!-- Toolbar -->
    <div class="format-toolbar">

      <!-- Block-style group -->
      <div class="fmt-group">
        <button class="fmt-icon-btn" :class="{ active: currentBlockStyle === 'paragraph' }" @click="setStyle('paragraph')" title="Normal text">¶</button>
        <button class="fmt-icon-btn fw7" :class="{ active: currentBlockStyle === 'heading-1' }" @click="setStyle('heading-1')" title="Heading 1" style="font-size:1rem">H1</button>
        <button class="fmt-icon-btn fw7" :class="{ active: currentBlockStyle === 'heading-2' }" @click="setStyle('heading-2')" title="Heading 2" style="font-size:0.85rem">H2</button>
        <button class="fmt-icon-btn fw7" :class="{ active: currentBlockStyle === 'heading-3' }" @click="setStyle('heading-3')" title="Heading 3" style="font-size:0.75rem">H3</button>
      </div>
      <div class="fmt-sep" />

      <!-- Block-type group -->
      <div class="fmt-group">
        <button class="fmt-icon-btn" :class="{ active: currentBlockStyle === 'quote' }" @click="setStyle('quote')" title="Block quote">❝</button>
        <button class="fmt-icon-btn" :class="{ active: currentBlockStyle === 'code' }" @click="setStyle('code')" title="Code block" style="font-size:0.72rem;letter-spacing:-1px">&lt;/&gt;</button>
        <button class="fmt-icon-btn" :class="{ active: currentBlockStyle === 'list-bullet' }" @click="setStyle('list-bullet')" title="Bullet list">☰</button>
        <button class="fmt-icon-btn" :class="{ active: currentBlockStyle === 'list-numbered' }" @click="setStyle('list-numbered')" title="Numbered list">①</button>
        <button class="fmt-icon-btn" :class="{ active: currentBlockStyle === 'checklist' }" @click="setStyle('checklist')" title="Checklist">☑</button>
      </div>
      <div class="fmt-sep" />

      <!-- Inline formatting group — mousedown.prevent keeps contenteditable focused -->
      <div class="fmt-group">
        <button class="fmt-icon-btn fmt-bold"      :class="{ active: fmtBold }"      title="Bold (Ctrl+B)"      @mousedown.prevent="applyFmt('bold')"><strong>B</strong></button>
        <button class="fmt-icon-btn fmt-italic"    :class="{ active: fmtItalic }"    title="Italic (Ctrl+I)"    @mousedown.prevent="applyFmt('italic')"><em>I</em></button>
        <button class="fmt-icon-btn fmt-underline" :class="{ active: fmtUnderline }" title="Underline (Ctrl+U)" @mousedown.prevent="applyFmt('underline')"><u>U</u></button>
      </div>

      <!-- Font-size picker -->
      <div class="fmt-group">
        <select class="fmt-size-select" title="Font size" @mousedown.stop @change="applySize">
          <option value="">Aₐ</option>
          <option value="12">12</option>
          <option value="15">15</option>
          <option value="18">18</option>
          <option value="22">22</option>
          <option value="28">28</option>
        </select>
      </div>

      <!-- Text color picker -->
      <div class="fmt-group fmt-color-wrap" @click.stop>
        <button
          class="fmt-icon-btn fmt-color-btn"
          title="Text color"
          @mousedown.prevent="toggleColorPicker"
        >
          <span class="fmt-color-letter">
            <span class="fmt-color-letter-text">A</span>
            <span class="fmt-color-letter-bar" :style="{ background: currentColor }" />
          </span>
        </button>
        <div v-if="showColorPicker" class="fmt-color-palette">
          <button
            v-for="c in colorPalette"
            :key="c"
            class="fmt-swatch"
            :class="{ active: currentColor === c }"
            :style="{ background: c }"
            :title="c"
            @mousedown.prevent="applyColor(c)"
          />
        </div>
      </div>
      <div class="fmt-sep" />

      <!-- Insert group -->
      <div class="fmt-group">
        <button class="fmt-icon-btn" title="Insert image" @click="fileInput?.click()">🖼</button>
        <button class="fmt-icon-btn" title="Draw"         @click="newDrawing">✏️</button>
        <button class="fmt-icon-btn" title="Divider"      @click="insertDivider" style="font-size:1.1rem;font-weight:300">—</button>
      </div>
    </div>

    <!-- Page -->
    <div class="blocks-container" dir="ltr" @click="onContainerClick">
      <BlockRenderer
        v-for="(block, i) in blocks"
        :key="block.id"
        :ref="el => { blockRefs[i] = el }"
        :block="block"
        :index="i"
        :is-selected="focusedIndex === i"
        @update="updateBlock(i, $event)"
        @delete="deleteBlock(i)"
        @focus="focusedIndex = i"
        @insert-after="insertAfter(i, $event)"
        @edit-drawing="startEditDrawing($event)"
      />
      <div class="page-rest" @click.stop="appendAndFocus" />
    </div>

    <!-- Drawing canvas overlay -->
    <div v-if="showDrawing" class="drawing-overlay">
      <DrawingCanvas
        :initial-data="drawingInitialData"
        @save="onDrawingSave"
        @close="showDrawing = false"
      />
    </div>

    <input ref="fileInput" type="file" accept="image/*" style="display:none" @change="onImageUpload" />
  </div>
</template>

<script setup>
import { ref, computed, watch, onMounted, onUnmounted, nextTick } from 'vue'
import BlockRenderer from './BlockRenderer.vue'
import DrawingCanvas from './DrawingCanvas.vue'

const props = defineProps({
  modelValue: { type: String, default: '' },
})
const emit = defineEmits(['update:modelValue'])

// ── State ──────────────────────────────────────────────────────────────────
const blocks    = ref([])
const blockRefs = ref([])
const focusedIndex        = ref(0)
const showDrawing         = ref(false)
const drawingInitialData  = ref(null)
const editingDrawingIndex = ref(null)
const fileInput = ref(null)
let uid = 1

function makeId() { return uid++ }

function emptyParagraph() {
  return { id: makeId(), type: 'paragraph', content: [{ insert: '' }] }
}

// ── Inline-format state (reflects cursor position) ─────────────────────────
const fmtBold      = ref(false)
const fmtItalic    = ref(false)
const fmtUnderline = ref(false)

// Color picker
const showColorPicker = ref(false)
const currentColor    = ref('#000000')

const colorPalette = [
  '#000000', '#5f6368', '#b0b0b0', '#ffffff',
  '#e53935', '#f4511e', '#f6bf26', '#33b679',
  '#039be5', '#3f51b5', '#8e24aa', '#d81b60',
]

function toggleColorPicker(e) {
  e.preventDefault()
  showColorPicker.value = !showColorPicker.value
}

function applyColor(color) {
  showColorPicker.value = false
  currentColor.value = color
  if (!savedRange) return

  // Restore saved selection
  const sel = window.getSelection()
  sel.removeAllRanges()
  sel.addRange(savedRange)

  if (savedRange.collapsed) return

  const span = document.createElement('span')
  span.style.color = color
  try {
    savedRange.surroundContents(span)
  } catch {
    const frag = savedRange.extractContents()
    span.appendChild(frag)
    savedRange.insertNode(span)
  }
  savedCE?.dispatchEvent(new InputEvent('input', { bubbles: true }))
}

function closeColorPicker(e) {
  if (showColorPicker.value) showColorPicker.value = false
}

// Keep a clone of the last selection inside a contenteditable
// so the font-size <select> can restore it after stealing focus.
let savedRange = null
let savedCE    = null   // the contenteditable element that owned the selection

function onSelectionChange() {
  const sel = window.getSelection()
  if (!sel || !sel.rangeCount) return
  const range    = sel.getRangeAt(0)
  const ancestor = range.commonAncestorContainer
  const el       = ancestor.nodeType === 1 ? ancestor : ancestor.parentElement
  if (!el?.closest('[contenteditable]')) return

  // Update toolbar toggle states
  fmtBold.value      = document.queryCommandState('bold')
  fmtItalic.value    = document.queryCommandState('italic')
  fmtUnderline.value = document.queryCommandState('underline')

  // Save for size picker
  savedRange = range.cloneRange()
  savedCE    = el.closest('[contenteditable]')
}

onMounted(() => {
  blocks.value = deserialize(props.modelValue)
  if (blocks.value.length === 0) blocks.value = [emptyParagraph()]
  document.addEventListener('selectionchange', onSelectionChange)
  document.addEventListener('click', closeColorPicker)
})

onUnmounted(() => {
  document.removeEventListener('selectionchange', onSelectionChange)
  document.removeEventListener('click', closeColorPicker)
})

// ── Apply inline formatting ────────────────────────────────────────────────

function applyFmt(cmd) {
  // mousedown.prevent keeps the contenteditable focused, so execCommand works
  document.execCommand(cmd, false, null)
  fmtBold.value      = document.queryCommandState('bold')
  fmtItalic.value    = document.queryCommandState('italic')
  fmtUnderline.value = document.queryCommandState('underline')
}

function applySize(event) {
  const px = event.target.value
  event.target.value = ''           // reset select to placeholder
  if (!px || !savedRange) return
  if (savedRange.collapsed) return  // need a selection to size

  // Restore the saved selection (select stole focus)
  const sel = window.getSelection()
  sel.removeAllRanges()
  sel.addRange(savedRange)

  // Wrap the selected content in a size span
  const span = document.createElement('span')
  span.style.fontSize = px + 'px'
  try {
    savedRange.surroundContents(span)
  } catch {
    // Selection crosses element boundaries — extract & re-insert
    const frag = savedRange.extractContents()
    span.appendChild(frag)
    savedRange.insertNode(span)
  }

  // Notify the contenteditable so the block stores updated ops
  savedCE?.dispatchEvent(new InputEvent('input', { bubbles: true }))
}

// ── Style picker (block type) ──────────────────────────────────────────────
const currentBlockStyle = computed(() => {
  const b = blocks.value[focusedIndex.value]
  if (!b) return 'paragraph'
  if (b.type === 'heading')   return `heading-${b.level || 1}`
  if (b.type === 'list')      return b.ordered ? 'list-numbered' : 'list-bullet'
  if (b.type === 'checklist') return 'checklist'
  if (b.type === 'quote')     return 'quote'
  if (b.type === 'code')      return 'code'
  return 'paragraph'
})

function setStyle(val) {
  const map = {
    'paragraph':     () => convertBlock('paragraph'),
    'heading-1':     () => convertBlock('heading', 1),
    'heading-2':     () => convertBlock('heading', 2),
    'heading-3':     () => convertBlock('heading', 3),
    'quote':         () => convertBlock('quote'),
    'list-bullet':   () => convertBlock('list', 0),
    'list-numbered': () => convertBlock('list', 1),
    'checklist':     () => convertBlock('checklist'),
    'code':          () => convertBlock('code'),
  }
  map[val]?.()
}

// ── Helpers ────────────────────────────────────────────────────────────────

// Normalize content: handle old { text } and new quill { insert } formats
function normalizeContent(content) {
  if (!Array.isArray(content) || !content.length) return [{ insert: '' }]
  return content.map(item => {
    if (item.insert !== undefined) return item
    if (item.text   !== undefined) return { insert: item.text }
    return { insert: '' }
  })
}

// Strip unknown quill attributes; keep only inline formatting attrs
function cleanOp(op) {
  const out = { insert: op.insert }
  if (op.attributes) {
    const a = {}
    if (op.attributes.bold)      a.bold = true
    if (op.attributes.italic)    a.italic = true
    if (op.attributes.underline) a.underline = true
    if (op.attributes.size)      a.size = String(op.attributes.size)
    if (op.attributes.color)     a.color = String(op.attributes.color)
    if (Object.keys(a).length)   out.attributes = a
  }
  return out
}

function blockPlainText(block) {
  if (block.content) return block.content.map(s => (s.insert ?? s.text ?? '')).join('')
  if (block.items)   return block.items.map(it => it.text || '').join(' ')
  if (block.code !== undefined) return block.code
  return ''
}

// ── Serialize → quill-1.0 (mobile reads natively, no migration needed) ─────
function serialize(blockList) {
  const ops    = []
  const images = {}
  let imgIdx   = 0

  for (const b of blockList) {
    if (b.type === 'paragraph' || b.type === 'quote') {
      const lineOps = normalizeContent(b.content)
      for (const op of lineOps) if (op.insert) ops.push(cleanOp(op))
      ops.push({ insert: '\n' })

    } else if (b.type === 'heading') {
      const lineOps = normalizeContent(b.content)
      for (const op of lineOps) if (op.insert) ops.push(cleanOp(op))
      ops.push({ insert: '\n', attributes: { header: b.level ?? 1 } })

    } else if (b.type === 'list') {
      const listType = b.ordered ? 'ordered' : 'bullet'
      for (const item of (b.items ?? [])) {
        const lineOps = normalizeContent(item.ops ?? [{ insert: item.text ?? '' }])
        for (const op of lineOps) if (op.insert) ops.push(cleanOp(op))
        ops.push({ insert: '\n', attributes: { list: listType } })
      }

    } else if (b.type === 'checklist') {
      for (const item of (b.items ?? [])) {
        const lineOps = normalizeContent(item.ops ?? [{ insert: item.text ?? '' }])
        for (const op of lineOps) if (op.insert) ops.push(cleanOp(op))
        ops.push({ insert: '\n', attributes: { list: item.checked ? 'checked' : 'unchecked' } })
      }

    } else if (b.type === 'code') {
      const lines = (b.code ?? '').split('\n')
      for (const line of lines) {
        if (line) ops.push({ insert: line })
        ops.push({ insert: '\n', attributes: { 'code-block': true } })
      }

    } else if (b.type === 'image') {
      const key = `img_${imgIdx++}`
      ops.push({ insert: { image: key } })
      ops.push({ insert: '\n' })
      images[key] = {
        data:     b.data,
        width:    b.displayWidth  ?? null,
        height:   b.displayHeight ?? null,
        rotation: b.rotation      ?? 0,
      }

    } else if (b.type === 'drawing') {
      const key = `drawing_${imgIdx++}`
      ops.push({ insert: { image: key } })
      ops.push({ insert: '\n' })
      images[key] = { data: b.data, width: null, height: null, rotation: 0 }

    } else if (b.type === 'divider') {
      ops.push({ insert: { divider: true } })
      ops.push({ insert: '\n' })
    }
  }

  return JSON.stringify({ version: 'quill-1.0', delta: ops, images, strokes: [] })
}

// ── Deserialize ────────────────────────────────────────────────────────────
watch(() => props.modelValue, (val) => {
  if (val !== serialize(blocks.value)) {
    blocks.value = deserialize(val)
    if (blocks.value.length === 0) blocks.value = [emptyParagraph()]
  }
})

function deserialize(raw) {
  if (!raw) return []
  try {
    const parsed = JSON.parse(raw)

    // ── quill-1.0 (mobile format) — preserve all inline formatting ops ──
    if (parsed.version === 'quill-1.0') {
      const ops    = parsed.delta ?? []
      const images = parsed.images ?? {}
      const result = []
      let lineOps  = []   // ops accumulator for the current line

      const flushLine = (newlineAttrs) => {
        const list   = newlineAttrs?.list
        const header = newlineAttrs?.header
        const isCode = newlineAttrs?.['code-block']

        if (isCode) {
          const text = lineOps.map(op => op.insert ?? '').join('')
          const last = result[result.length - 1]
          if (last?.type === 'code') {
            last.code += '\n' + text
          } else {
            result.push({ id: makeId(), type: 'code', language: 'plain', code: text })
          }

        } else if (list === 'bullet' || list === 'ordered') {
          const text = lineOps.map(op => op.insert ?? '').join('')
          result.push({ id: makeId(), type: 'list', ordered: list === 'ordered', items: [{ text, ops: [...lineOps] }] })

        } else if (list === 'checked' || list === 'unchecked') {
          const text = lineOps.map(op => op.insert ?? '').join('')
          result.push({ id: makeId(), type: 'checklist', items: [{ text, checked: list === 'checked', ops: [...lineOps] }] })

        } else if (header) {
          result.push({ id: makeId(), type: 'heading', level: header, content: lineOps.length ? [...lineOps] : [{ insert: '' }] })

        } else {
          result.push({ id: makeId(), type: 'paragraph', content: lineOps.length ? [...lineOps] : [{ insert: '' }] })
        }

        lineOps = []
      }

      for (const op of ops) {
        if (typeof op.insert === 'object') {
          if (op.insert?.image) {
            if (lineOps.length) flushLine({})
            const img = images[op.insert.image]
            if (img?.data) {
              result.push({
                id: makeId(), type: 'image',
                data: img.data, caption: '',
                displayWidth:  img.width    || null,
                displayHeight: img.height   || null,
                rotation:      img.rotation || 0,
              })
            }
          } else if (op.insert?.divider) {
            if (lineOps.length) flushLine({})
            result.push({ id: makeId(), type: 'divider' })
          }

        } else if (typeof op.insert === 'string') {
          const parts = op.insert.split('\n')
          for (let i = 0; i < parts.length; i++) {
            const chunk = parts[i]
            if (chunk) {
              // Only carry inline attrs (not block-level like header/list)
              const lineOp = { insert: chunk }
              if (op.attributes) {
                const inline = {}
                if (op.attributes.bold)      inline.bold = true
                if (op.attributes.italic)    inline.italic = true
                if (op.attributes.underline) inline.underline = true
                if (op.attributes.size)      inline.size = String(op.attributes.size)
                if (op.attributes.color)     inline.color = String(op.attributes.color)
                if (Object.keys(inline).length) lineOp.attributes = inline
              }
              lineOps.push(lineOp)
            }
            if (i < parts.length - 1) flushLine(op.attributes ?? {})
          }
        }
      }
      if (lineOps.length) flushLine({})

      if (parsed.strokes?.length) {
        const dataUrl = strokesToDataUrl(parsed.strokes)
        if (dataUrl) result.push({ id: makeId(), type: 'drawing', data: dataUrl, _strokes: parsed.strokes })
      }

      return result.length ? result : []
    }

    // ── Legacy v2.0 format ──────────────────────────────────────────────
    if (parsed.version === '2.0') {
      const result = []
      for (const p of (parsed.paragraphs ?? [])) {
        const style = p.style || 'normal'
        const ops   = [{ insert: p.text || '' }]
        if (style === 'h1')           result.push({ id: makeId(), type: 'heading',   level: 1, content: ops })
        else if (style === 'h2')      result.push({ id: makeId(), type: 'heading',   level: 2, content: ops })
        else if (style === 'h3')      result.push({ id: makeId(), type: 'heading',   level: 3, content: ops })
        else if (style === 'bullet')  result.push({ id: makeId(), type: 'list',      ordered: false, items: [{ text: p.text || '' }] })
        else if (style === 'numbered')result.push({ id: makeId(), type: 'list',      ordered: true,  items: [{ text: p.text || '' }] })
        else if (style === 'checklist')result.push({ id: makeId(), type: 'checklist',items: [{ text: p.text || '', checked: p.checked ?? false }] })
        else                          result.push({ id: makeId(), type: 'paragraph', content: ops })
      }
      for (const img of (parsed.images ?? [])) {
        result.push({ id: makeId(), type: 'image', data: img.data || '', caption: '', displayWidth: img.width || null, displayHeight: img.height || null, rotation: img.rotation || 0 })
      }
      if (parsed.strokes?.length) {
        const dataUrl = strokesToDataUrl(parsed.strokes)
        if (dataUrl) result.push({ id: makeId(), type: 'drawing', data: dataUrl, _strokes: parsed.strokes })
      }
      return result.length ? result : []
    }

    // ── v1.0 web blocks — copy as-is (normalizeContent handles old { text } format) ──
    const list   = parsed.blocks ?? []
    const result = list.map(b => {
      const block = { ...b, id: makeId() }
      if (b.type === 'drawing' && b.strokes?.length) block._strokes = b.strokes
      return block
    })
    return result.length ? result : []

  } catch {
    return markdownToBlocks(raw)
  }
}

function markdownToBlocks(md) {
  const lines  = md.split('\n')
  const result = []
  let i = 0
  while (i < lines.length) {
    const line = lines[i]
    if      (/^### /.test(line))  result.push({ id: makeId(), type: 'heading', level: 3, content: [{ insert: line.slice(4) }] })
    else if (/^## /.test(line))   result.push({ id: makeId(), type: 'heading', level: 2, content: [{ insert: line.slice(3) }] })
    else if (/^# /.test(line))    result.push({ id: makeId(), type: 'heading', level: 1, content: [{ insert: line.slice(2) }] })
    else if (/^> /.test(line))    result.push({ id: makeId(), type: 'quote',   content: [{ insert: line.slice(2) }] })
    else if (/^```/.test(line)) {
      const lang = line.slice(3).trim()
      const codeLines = []
      i++
      while (i < lines.length && !/^```/.test(lines[i])) { codeLines.push(lines[i]); i++ }
      result.push({ id: makeId(), type: 'code', language: lang || 'plain', code: codeLines.join('\n') })
    }
    else if (/^---$/.test(line))  result.push({ id: makeId(), type: 'divider' })
    else if (/^!\[/.test(line)) {
      const m = line.match(/^!\[([^\]]*)\]\(([^)]+)\)/)
      if (m) result.push({ id: makeId(), type: 'image', caption: m[1], data: m[2] })
    }
    else if (/^[-*] \[[ x]\]/.test(line)) {
      result.push({ id: makeId(), type: 'checklist', items: [{ text: line.slice(6), checked: line[4] === 'x' }] })
    }
    else if (/^[-*] /.test(line)) result.push({ id: makeId(), type: 'list', ordered: false, items: [{ text: line.slice(2) }] })
    else if (/^\d+\. /.test(line))result.push({ id: makeId(), type: 'list', ordered: true,  items: [{ text: line.replace(/^\d+\. /, '') }] })
    else if (line.trim())         result.push({ id: makeId(), type: 'paragraph', content: [{ insert: line }] })
    i++
  }
  return result
}

function emitChange() {
  emit('update:modelValue', serialize(blocks.value))
}

// ── Block operations ──────────────────────────────────────────────────────
function updateBlock(i, updated) {
  blocks.value[i] = { ...updated, id: blocks.value[i].id }
  emitChange()
}

function deleteBlock(i) {
  if (blocks.value.length === 1) {
    blocks.value = [emptyParagraph()]
  } else {
    blocks.value.splice(i, 1)
    focusedIndex.value = Math.max(0, i - 1)
  }
  emitChange()
  nextTick(() => focusBlock(focusedIndex.value))
}

function insertAfter(i, type = 'paragraph') {
  const newBlock = makeBlock(type)
  blocks.value.splice(i + 1, 0, newBlock)
  focusedIndex.value = i + 1
  emitChange()
  nextTick(() => focusBlock(i + 1))
}

function makeBlock(type, extra = {}) {
  switch (type) {
    case 'heading':   return { id: makeId(), type: 'heading',   level: extra.level ?? 1, content: [{ insert: '' }] }
    case 'quote':     return { id: makeId(), type: 'quote',     content: [{ insert: '' }] }
    case 'code':      return { id: makeId(), type: 'code',      language: 'plain', code: '' }
    case 'list':      return { id: makeId(), type: 'list',      ordered: !!extra.ordered, items: [{ text: '' }] }
    case 'checklist': return { id: makeId(), type: 'checklist', items: [{ text: '', checked: false }] }
    case 'divider':   return { id: makeId(), type: 'divider' }
    default:          return emptyParagraph()
  }
}

function focusBlock(i) {
  blockRefs.value[i]?.focus()
}

function appendAndFocus() {
  if (blocks.value.length === 0) {
    blocks.value = [emptyParagraph()]
    emitChange()
    nextTick(() => focusBlock(0))
    return
  }
  const last     = blocks.value[blocks.value.length - 1]
  const lastText = last.content
    ? last.content.map(s => (s.insert ?? s.text ?? '')).join('')
    : ''
  const needNew  = last.type !== 'paragraph' || lastText !== ''
  if (needNew) {
    blocks.value.push(emptyParagraph())
    emitChange()
  }
  focusedIndex.value = blocks.value.length - 1
  nextTick(() => focusBlock(blocks.value.length - 1))
}

// ── Convert focused block style ────────────────────────────────────────────
function convertBlock(type, extra) {
  const i = focusedIndex.value
  if (i < 0 || i >= blocks.value.length) return
  const cur = blocks.value[i]

  // Preserve inline-formatted ops when switching between text-bearing types
  const curOps   = cur.content ? normalizeContent(cur.content) : [{ insert: blockPlainText(cur) }]
  const plainTxt = blockPlainText(cur)

  let newBlock
  if      (type === 'paragraph') newBlock = { id: cur.id, type: 'paragraph', content: curOps }
  else if (type === 'heading')   newBlock = { id: cur.id, type: 'heading',   level: extra ?? 1, content: curOps }
  else if (type === 'quote')     newBlock = { id: cur.id, type: 'quote',     content: curOps }
  else if (type === 'list')      newBlock = { id: cur.id, type: 'list',      ordered: !!extra, items: [{ text: plainTxt }] }
  else if (type === 'checklist') newBlock = { id: cur.id, type: 'checklist', items: [{ text: plainTxt, checked: false }] }
  else if (type === 'code')      newBlock = { id: cur.id, type: 'code',      language: 'plain', code: plainTxt }
  else return

  blocks.value[i] = newBlock
  emitChange()
  nextTick(() => focusBlock(i))
}

function onContainerClick() { /* background click — nothing special */ }

function insertDivider() {
  const i = focusedIndex.value >= 0 ? focusedIndex.value : blocks.value.length - 1
  blocks.value.splice(i + 1, 0, { id: makeId(), type: 'divider' })
  blocks.value.splice(i + 2, 0, emptyParagraph())
  focusedIndex.value = i + 2
  emitChange()
  nextTick(() => focusBlock(i + 2))
}

// ── Image upload ──────────────────────────────────────────────────────────
function onImageUpload(event) {
  const file = event.target.files?.[0]
  if (!file) return
  const reader = new FileReader()
  reader.onload = (e) => {
    const i = focusedIndex.value >= 0 ? focusedIndex.value : blocks.value.length - 1
    blocks.value.splice(i + 1, 0, { id: makeId(), type: 'image', data: e.target.result, filename: file.name, caption: '' })
    focusedIndex.value = i + 1
    emitChange()
  }
  reader.readAsDataURL(file)
  event.target.value = ''
}

// ── Drawing ───────────────────────────────────────────────────────────────
function newDrawing() {
  drawingInitialData.value  = null
  editingDrawingIndex.value = null
  showDrawing.value         = true
}

function startEditDrawing(block) {
  editingDrawingIndex.value = blocks.value.findIndex(b => b.id === block.id)
  drawingInitialData.value  = block._strokes?.length ? { strokes: block._strokes } : null
  showDrawing.value         = true
}

function onDrawingSave({ dataUrl, strokes }) {
  showDrawing.value = false
  const drawingBlock = { id: makeId(), type: 'drawing', data: dataUrl, _strokes: strokes }
  if (editingDrawingIndex.value !== null && editingDrawingIndex.value >= 0) {
    blocks.value[editingDrawingIndex.value] = drawingBlock
  } else {
    const i = focusedIndex.value >= 0 ? focusedIndex.value : blocks.value.length - 1
    blocks.value.splice(i + 1, 0, drawingBlock)
    focusedIndex.value = i + 1
  }
  emitChange()
}

// ── Stroke → PNG ──────────────────────────────────────────────────────────
function strokesToDataUrl(strokes) {
  try {
    const W = 800, H = 500
    const canvas = document.createElement('canvas')
    canvas.width = W; canvas.height = H
    const ctx = canvas.getContext('2d')
    ctx.fillStyle = '#1e1e2e'
    ctx.fillRect(0, 0, W, H)
    const nonEraser = strokes.filter(s => !s.eraser)
    if (!nonEraser.length) return null
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
    for (const s of nonEraser) for (const pt of (s.pts || [])) {
      if (pt[0] < minX) minX = pt[0]; if (pt[1] < minY) minY = pt[1]
      if (pt[0] > maxX) maxX = pt[0]; if (pt[1] > maxY) maxY = pt[1]
    }
    const pad   = 16
    const scale = Math.min((W - pad*2) / Math.max(maxX-minX,1), (H - pad*2) / Math.max(maxY-minY,1), 1)
    const dx    = pad - minX*scale
    const dy    = pad - minY*scale
    for (const s of nonEraser) {
      const pts = s.pts || []
      if (pts.length < 2) continue
      let color = '#ffffff'
      try { const hex = (s.color||'').replace(/^0x/i,''); color = '#'+(hex.length===8?hex.slice(2):hex) } catch {}
      ctx.strokeStyle = color
      ctx.lineWidth   = Math.max(1, (s.width||2)*scale)
      ctx.lineCap = 'round'; ctx.lineJoin = 'round'
      ctx.beginPath()
      ctx.moveTo(pts[0][0]*scale+dx, pts[0][1]*scale+dy)
      for (let j = 1; j < pts.length; j++) ctx.lineTo(pts[j][0]*scale+dx, pts[j][1]*scale+dy)
      ctx.stroke()
    }
    return canvas.toDataURL('image/png')
  } catch { return null }
}
</script>

<style lang="scss" scoped>
.block-editor {
  display: flex;
  flex-direction: column;
  flex: 1;
}

// ── Toolbar ───────────────────────────────────────────────────────────────
.format-toolbar {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 6px 0 10px;
  border-bottom: 1px solid var(--color-border);
  margin-bottom: 4px;
  flex-wrap: wrap;
}

.fmt-group {
  display: flex;
  align-items: center;
  gap: 2px;
}

.fmt-icon-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 30px;
  height: 28px;
  border: 1px solid transparent;
  border-radius: 5px;
  background: transparent;
  cursor: pointer;
  font-size: 0.9rem;
  color: var(--color-main-text);
  transition: background 0.1s;
  padding: 0;

  &:hover {
    background: var(--color-background-hover);
    border-color: var(--color-border);
  }

  &.active {
    background: var(--color-primary-element-light, rgba(0,130,201,0.15));
    border-color: var(--color-primary-element);
    color: var(--color-primary-element);
  }

  &.fw7       { font-weight: 700; }
  &.fmt-bold  { font-weight: 700; font-size: 1rem; }
  &.fmt-italic    { font-style: italic; font-size: 1rem; }
  &.fmt-underline { text-decoration: underline; font-size: 1rem; }
}

.fmt-size-select {
  height: 28px;
  min-width: 54px;
  border: 1px solid var(--color-border);
  border-radius: 5px;
  background: var(--color-background-dark, #f2f2f2);
  color: var(--color-main-text);
  font-size: 0.82rem;
  font-weight: 600;
  padding: 0 6px;
  cursor: pointer;

  &:focus { outline: none; border-color: var(--color-primary-element); }
  option { font-weight: 400; }
}

.fmt-sep {
  width: 1px;
  height: 20px;
  background: var(--color-border);
  flex-shrink: 0;
  margin: 0 2px;
}

// ── Color picker ──────────────────────────────────────────────────────────
.fmt-color-wrap {
  position: relative;
}

.fmt-color-btn {
  min-width: 30px;
}

.fmt-color-letter {
  display: inline-flex;
  flex-direction: column;
  align-items: center;
  gap: 1px;
}

.fmt-color-letter-text {
  font-weight: 700;
  font-size: 1rem;
  line-height: 1;
  color: var(--color-main-text);
}

.fmt-color-letter-bar {
  display: block;
  width: 14px;
  height: 3px;
  border-radius: 2px;
}

.fmt-color-palette {
  position: absolute;
  top: calc(100% + 6px);
  left: 0;
  z-index: 200;
  display: grid;
  grid-template-columns: repeat(4, 22px);
  gap: 4px;
  padding: 8px;
  background: var(--color-main-background);
  border: 1px solid var(--color-border);
  border-radius: 8px;
  box-shadow: 0 4px 16px rgba(0,0,0,0.18);
}

.fmt-swatch {
  width: 22px;
  height: 22px;
  border-radius: 50%;
  border: 2px solid transparent;
  cursor: pointer;
  padding: 0;
  outline: none;
  transition: transform 0.1s;

  &:hover { transform: scale(1.15); }

  &.active {
    border-color: var(--color-primary-element);
    box-shadow: 0 0 0 1px var(--color-primary-element);
  }

  // Special cases that need a visible border against white/light backgrounds
  &[style*='background: rgb(255, 255, 255)'],
  &[style*='background: #ffffff'] { border-color: var(--color-border); }
  &[style*='background: rgb(176, 176, 176)'],
  &[style*='background: #b0b0b0'] { border-color: var(--color-border); }
}

// ── Page ──────────────────────────────────────────────────────────────────
.blocks-container {
  flex: 1;
  padding: 4px 0 0;
  display: flex;
  flex-direction: column;
}

.page-rest {
  flex: 1;
  min-height: 200px;
  cursor: text;
}

// ── Drawing overlay ───────────────────────────────────────────────────────
.drawing-overlay {
  position: fixed;
  inset: 0;
  z-index: 100;
  background: var(--color-main-background);
}
</style>
