import { test } from 'node:test'
import assert from 'node:assert/strict'
import { colorToCss, referenceWidth, strokesBottom, drawStrokes, parseRgb, readableInk, toReferencePoint, hexToAndroid, makeStroke, nextStrokesWidth } from '../src/composables/strokes.js'
import { buildNoteJson } from '../src/composables/noteContent.js'

/** A canvas context that records what is drawn. */
function fakeCtx() {
  const calls = []
  const ctx = {
    calls,
    globalCompositeOperation: 'source-over',
    strokeStyle: '',
    fillStyle: '',
    lineWidth: 0,
    lineCap: '',
    lineJoin: '',
    stack: [],
    save() { calls.push(['save']); ctx.stack.push(ctx.globalCompositeOperation) },
    restore() { calls.push(['restore']); ctx.globalCompositeOperation = ctx.stack.pop() },
    beginPath() { calls.push(['beginPath']) },
    moveTo(x, y) { calls.push(['moveTo', x, y]) },
    lineTo(x, y) { calls.push(['lineTo', x, y]) },
    quadraticCurveTo(a, b, c, d) { calls.push(['quad', a, b, c, d]) },
    arc(x, y, r) { calls.push(['arc', x, y, r]) },
    stroke() { calls.push(['stroke', ctx.strokeStyle, ctx.lineWidth, ctx.globalCompositeOperation]) },
    fill() { calls.push(['fill', ctx.fillStyle, ctx.globalCompositeOperation]) },
  }
  return ctx
}

const line = { pts: [[10, 10], [20, 20], [30, 10]], color: '0xff112233', width: 4, eraser: false }

test('colour: Android 0xAARRGGBB becomes CSS rgba', () => {
  assert.equal(colorToCss('0xff112233'), 'rgba(17, 34, 51, 1)')
  assert.equal(colorToCss('0x80ff0000'), 'rgba(255, 0, 0, 0.502)')
  assert.equal(colorToCss('#00ff00'), 'rgba(0, 255, 0, 1)')
  assert.equal(colorToCss('garbage'), 'rgba(0, 0, 0, 1)', 'unreadable colour falls back to black')
  assert.equal(colorToCss(undefined), 'rgba(0, 0, 0, 1)')
})

test('reference width: the saved page width, else a phone width widened to fit the drawing', () => {
  assert.equal(referenceWidth([line], 412), 412)
  assert.equal(referenceWidth([line], 0), 360, 'no width saved: assume a phone')
  assert.equal(referenceWidth([{ ...line, pts: [[5, 5], [500, 9]] }], undefined), 516, 'wider than a phone: fit the drawing')
  assert.equal(referenceWidth([], undefined), 360)
})

test('strokesBottom is the lowest point, ignoring junk', () => {
  assert.equal(strokesBottom([line, { pts: [[1, 400]] }]), 400)
  assert.equal(strokesBottom([]), 0)
  assert.equal(strokesBottom([{ pts: 'x' }, null, {}]), 0)
})

test('draws a stroke as a smooth path in its colour, scaled and scrolled', () => {
  const ctx = fakeCtx()
  drawStrokes(ctx, [line], { scale: 2, offsetY: 5 })
  const kinds = ctx.calls.map((c) => c[0])
  assert.ok(kinds.includes('moveTo') && kinds.includes('quad') && kinds.includes('stroke'))
  assert.deepEqual(ctx.calls.find((c) => c[0] === 'moveTo'), ['moveTo', 20, 15], 'x*2, y*2 - 5')
  const st = ctx.calls.find((c) => c[0] === 'stroke')
  assert.equal(st[1], 'rgba(17, 34, 51, 1)')
  assert.equal(st[2], 8, 'width scales too')
  assert.equal(st[3], 'source-over')
})

test('an eraser stroke removes earlier ink instead of painting', () => {
  const ctx = fakeCtx()
  drawStrokes(ctx, [line, { ...line, eraser: true, width: 12 }], { scale: 1, offsetY: 0 })
  const strokes = ctx.calls.filter((c) => c[0] === 'stroke')
  assert.equal(strokes[0][3], 'source-over')
  assert.equal(strokes[1][3], 'destination-out')
  assert.equal(ctx.globalCompositeOperation, 'source-over', 'state is restored afterwards')
})

test('a single tap is drawn as a dot', () => {
  const ctx = fakeCtx()
  drawStrokes(ctx, [{ pts: [[50, 60]], color: '0xff000000', width: 6, eraser: false }], { scale: 1, offsetY: 0 })
  assert.ok(ctx.calls.some((c) => c[0] === 'arc'))
  assert.ok(ctx.calls.some((c) => c[0] === 'fill'))
})

test('malformed strokes are skipped, the rest still draw', () => {
  const ctx = fakeCtx()
  drawStrokes(ctx, [null, { pts: 'nope' }, { pts: [] }, line], { scale: 1, offsetY: 0 })
  assert.equal(ctx.calls.filter((c) => c[0] === 'stroke').length, 1)
})

test('saving a note from the web keeps the Android drawing (it used to be wiped)', () => {
  const strokes = [line]
  const json = JSON.parse(buildNoteJson({ delta: [{ insert: 'hi\n' }], images: {}, strokes, strokesWidth: 360 }))
  assert.equal(json.version, 'quill-1.0')
  assert.deepEqual(json.strokes, strokes)
  assert.equal(json.strokesWidth, 360)
})

test('unused images are pruned, used ones kept, and no strokesWidth is invented', () => {
  const json = JSON.parse(buildNoteJson({
    delta: [{ insert: { image: 'a' } }, { insert: '\n' }],
    images: { a: { data: 'x' }, b: { data: 'y' } },
    strokes: [],
  }))
  assert.deepEqual(Object.keys(json.images), ['a'])
  assert.equal('strokesWidth' in json, false)
  assert.deepEqual(json.strokes, [])
})

test('parseRgb reads the colours the browser reports', () => {
  assert.deepEqual(parseRgb('rgb(23, 23, 23)'), [23, 23, 23, 1])
  assert.deepEqual(parseRgb('rgba(0, 0, 0, 0)'), [0, 0, 0, 0])
  assert.deepEqual(parseRgb('#ffffff'), [255, 255, 255, 1])
  assert.equal(parseRgb('transparent'), null)
})

test('ink that would vanish on the page background is shown in the page text colour', () => {
  const white = [255, 255, 255], dark = [23, 23, 23], text = [30, 30, 30], lightText = [235, 235, 235]
  assert.equal(readableInk('rgba(255, 255, 255, 1)', white, text), 'rgba(30, 30, 30, 1)', 'white pen on a light page')
  assert.equal(readableInk('rgba(0, 0, 0, 1)', dark, lightText), 'rgba(235, 235, 235, 1)', 'black pen on a dark page')
  assert.equal(readableInk('rgba(255, 255, 255, 1)', dark, lightText), 'rgba(255, 255, 255, 1)', 'white on dark stays white')
  assert.equal(readableInk('rgba(0, 0, 0, 1)', white, text), 'rgba(0, 0, 0, 1)', 'black on light stays black')
  assert.equal(readableInk('rgba(220, 30, 30, 1)', white, text), 'rgba(220, 30, 30, 1)', 'colours are kept')
  assert.equal(readableInk('rgba(255, 255, 255, 0.5)', white, text), 'rgba(30, 30, 30, 0.5)', 'keeps the transparency')
})

test('drawStrokes uses the readable ink when told the page colours', () => {
  const ctx = fakeCtx()
  const whiteStroke = { ...line, color: '0xffffffff' }
  drawStrokes(ctx, [whiteStroke], { scale: 1, offsetY: 0, background: [255, 255, 255], foreground: [30, 30, 30] })
  assert.equal(ctx.calls.find((c) => c[0] === 'stroke')[1], 'rgba(30, 30, 30, 1)')
})

test('web pointer positions become the phone page units (zoom and scroll removed)', () => {
  assert.deepEqual(toReferencePoint(200, 100, { scale: 2, scrollTop: 0 }), [100, 50])
  assert.deepEqual(toReferencePoint(200, 100, { scale: 2, scrollTop: 40 }), [100, 70], 'scrolled content: y + scrollTop')
  assert.deepEqual(toReferencePoint(10.123456, 5, { scale: 1, scrollTop: 0 }), [10.12, 5], 'rounded to keep the note small')
})

test('colour picker value becomes the Android 0xAARRGGBB string', () => {
  assert.equal(hexToAndroid('#ff8800'), '0xffff8800')
  assert.equal(hexToAndroid('#000000'), '0xff000000')
  assert.equal(hexToAndroid('nonsense'), '0xff000000')
})

test('a stroke is saved exactly as the phone saves it, the eraser three times wider', () => {
  const pen = makeStroke({ points: [[1, 2], [3, 4]], color: '#112233', width: 4, eraser: false })
  assert.deepEqual(pen, { pts: [[1, 2], [3, 4]], color: '0xff112233', width: 4, eraser: false })
  const er = makeStroke({ points: [[1, 2]], color: '#ffffff', width: 4, eraser: true })
  assert.equal(er.width, 12)
  assert.equal(er.eraser, true)
})

test('the saved page width: kept if the note has one, else the phone width', () => {
  assert.equal(nextStrokesWidth([], 0), 360, 'first drawing on a note: phone width')
  assert.equal(nextStrokesWidth([line], 412), 412, 'note already has one: keep it')
  assert.equal(nextStrokesWidth([{ ...line, pts: [[5, 5], [500, 9]] }], 0), 516, 'older phone drawing without a width: same guess as when showing it')
})

test('a stroke the web draws is shown again exactly like a phone stroke', () => {
  const ctx = fakeCtx()
  const s = makeStroke({ points: [[10, 10], [20, 30], [40, 10]], color: '#ff0000', width: 6, eraser: false })
  drawStrokes(ctx, [s], { scale: 1, offsetY: 0 })
  const st = ctx.calls.find((c) => c[0] === 'stroke')
  assert.equal(st[1], 'rgba(255, 0, 0, 1)')
  assert.equal(st[2], 6)
})

import { FONT_SIZES, toPxSize, fromPxSize } from '../src/composables/fontSize.js'
import { rgbToHex } from '../src/composables/strokes.js'

test('font sizes: the phone writes "28", the web used to write "28px": both are understood', () => {
  assert.equal(toPxSize('28'), '28px')
  assert.equal(toPxSize('28px'), '28px')
  assert.equal(toPxSize(22), '22px')
  assert.equal(toPxSize('big'), 'big', 'unreadable is left alone')
  assert.equal(fromPxSize('28px'), '28')
  assert.equal(fromPxSize('28'), '28')
  assert.equal(fromPxSize(''), '')
  assert.equal(fromPxSize(undefined), undefined)
  assert.deepEqual(FONT_SIZES, ['12', '15', '18', '22', '28'])
})

test('the pen colour shown is the colour saved: rgb to the colour picker hex', () => {
  assert.equal(rgbToHex([235, 235, 235]), '#ebebeb')
  assert.equal(rgbToHex([255, 255, 255]), '#ffffff')
  assert.equal(rgbToHex([0, 0, 0]), '#000000')
  assert.equal(rgbToHex([300, -4, 7.6]), '#ff0008', 'clamped and rounded')
})
