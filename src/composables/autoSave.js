/**
 * Saves unsaved changes on a fixed interval instead of after every edit.
 *
 * The timer starts at the FIRST change after a save and is not pushed back by later edits, so steady
 * typing is still saved once per `interval`. `flush()` saves right away (leaving the editor, the tab being
 * hidden or closed). A failed save, or an edit made while a save runs, stays unsaved and is retried on the
 * next interval.
 *
 * With a `snapshot` callback (a string that changes whenever the note's content changes), nothing is written
 * while the note is identical to the last saved version: typing something and undoing it does not rewrite the
 * note or change its modified time. Call `setBaseline()` once the note has loaded.
 */
export function createAutoSaver({ interval, save, snapshot }) {
  let baseline = null
  let timer = null
  let dirty = false
  let saving = false
  let disposed = false

  function schedule() {
    if (timer === null && !disposed) timer = setTimeout(onTimer, interval)
  }

  function onTimer() {
    timer = null
    run()
  }

  async function run() {
    if (!dirty || saving) return
    const snap = snapshot ? snapshot() : null
    if (snap !== null && snap === baseline) {
      dirty = false // changed and changed back: nothing to write
      return
    }
    saving = true
    dirty = false
    try {
      await save()
      if (snap !== null) baseline = snap
    } catch (e) {
      dirty = true
    } finally {
      saving = false
      if (dirty) schedule()
    }
  }

  return {
    /** Remembers the current content as "what is saved", e.g. right after the note was loaded. */
    setBaseline() { baseline = snapshot ? snapshot() : null },
    /** Call on every edit. Nothing is written here. */
    markDirty() {
      if (disposed) return
      dirty = true
      if (!saving) schedule() // while saving, the running save reschedules when it finishes
    },
    /** Saves now if there is anything unsaved, and cancels the pending timer. */
    async flush() {
      if (timer !== null) { clearTimeout(timer); timer = null }
      if (dirty) await run()
    },
    dirty: () => dirty,
    dispose() {
      disposed = true
      if (timer !== null) { clearTimeout(timer); timer = null }
    },
  }
}
