import { Controller } from "@hotwired/stimulus"

/*
  Small countries are a few pixels wide, so the map can be zoomed and moved
  rather than only squinted at. Done by moving the viewBox, so the shapes stay
  sharp and the readout keeps finding them under the pointer.
*/
export default class extends Controller {
  static targets = [ "svg", "in", "out" ]
  static step = 1.6
  // Eight times in is as far as the shapes carry detail.
  static reach = 8

  static tapGap = 300
  static tapSlop = 24

  connect() {
    this.touches = new Map()
    const box = this.svgTarget.viewBox.baseVal
    this.base = { x: box.x, y: box.y, w: box.width, h: box.height }
    this.view = { ...this.base }
  }

  /*
    Toward the pointer, so what's under it stays put. Only with ctrl or cmd
    held, so the page itself can still be scrolled past the map.
  */
  wheel(event) {
    if (!event.ctrlKey && !event.metaKey) return

    event.preventDefault()
    this.zoom(Math.exp(event.deltaY * 0.01), event)
  }

  in() {
    this.zoomCentre(1 / this.constructor.step)
  }

  out() {
    this.zoomCentre(this.constructor.step)
  }

  // About the middle, since a button has no pointer position to keep still.
  zoomCentre(factor) {
    const box = this.svgTarget.getBoundingClientRect()
    this.zoom(factor, { clientX: box.left + box.width / 2, clientY: box.top + box.height / 2 })
  }

  double(event) {
    if (this.control(event)) return

    this.zoom(event.shiftKey ? this.constructor.step : 1 / this.constructor.step, event)
  }

  // A press on a button is a click, which a captured pointer would swallow.
  control(event) {
    return !!event.target.closest?.("[data-map-zoom-control]")
  }

  zoom(factor, event) {
    const box = this.svgTarget.getBoundingClientRect()
    const across = (event.clientX - box.left) / box.width
    const down = (event.clientY - box.top) / box.height
    const w = Math.min(this.base.w, Math.max(this.base.w / this.constructor.reach, this.view.w * factor))
    const h = w * this.base.h / this.base.w
    this.view = { x: this.view.x + (this.view.w - w) * across, y: this.view.y + (this.view.h - h) * down, w, h }
    this.apply()
  }

  /*
    Only once zoomed, so a whole map's clicks and drags still reach the
    readout. Taken before the readout sees it, since a drag that moves the
    map would otherwise also hold a country's figures.
  */
  grab(event) {
    if (this.control(event)) return
    if (event.pointerType === "touch") return this.touch(event)
    if (this.view.w >= this.base.w || event.button !== 0) return

    event.stopPropagation()
    this.panning = { x: event.clientX, y: event.clientY, view: { ...this.view }, taken: true }
    this.cursor()
    this.element.setPointerCapture?.(event.pointerId)
  }

  drag(event) {
    if (this.touches.has(event.pointerId)) return this.move(event)

    this.pan(event)
  }

  pan(event) {
    if (!this.panning) return

    if (!this.panning.taken) {
      if (Math.hypot(event.clientX - this.panning.x, event.clientY - this.panning.y) < this.constructor.tapSlop) return
      this.panning.taken = true
    }
    event.stopPropagation()
    const box = this.svgTarget.getBoundingClientRect()
    this.view.x = this.panning.view.x - (event.clientX - this.panning.x) / box.width * this.view.w
    this.view.y = this.panning.view.y - (event.clientY - this.panning.y) / box.height * this.view.h
    this.apply()
  }

  release(event) {
    if (this.touches.delete(event.pointerId)) return this.lift(event)
    if (!this.panning) return

    event.stopPropagation()
    this.panning = null
    this.cursor()
  }

  /*
    Touch has neither a wheel nor a double click to rely on.
  */
  touch(event) {
    const now = event.timeStamp
    const last = this.tap
    this.touches.set(event.pointerId, { x: event.clientX, y: event.clientY, start: { x: event.clientX, y: event.clientY } })

    if (this.touches.size === 2) {
      event.stopPropagation()
      this.panning = null
      this.tap = null
      this.span = this.spread()
      return
    }

    if (last && now - last.at < this.constructor.tapGap && Math.hypot(event.clientX - last.x, event.clientY - last.y) < this.constructor.tapSlop) {
      event.stopPropagation()
      this.tap = null
      return this.zoom(1 / this.constructor.step, event)
    }
    this.tap = { at: now, x: event.clientX, y: event.clientY, moved: false }
    if (this.view.w >= this.base.w) return

    // Not taken until the finger moves, so a tap still reaches the readout.
    this.panning = { x: event.clientX, y: event.clientY, view: { ...this.view }, taken: false }
  }

  move(event) {
    const finger = this.touches.get(event.pointerId)
    finger.x = event.clientX
    finger.y = event.clientY
    if (this.tap && Math.hypot(finger.x - finger.start.x, finger.y - finger.start.y) > this.constructor.tapSlop) this.tap = null

    if (this.touches.size >= 2) {
      event.stopPropagation()
      const span = this.spread()
      const [ a, b ] = [ ...this.touches.values() ]
      if (span > 0 && this.span > 0) this.zoom(this.span / span, { clientX: (a.x + b.x) / 2, clientY: (a.y + b.y) / 2 })
      this.span = span
      return
    }
    this.pan(event)
  }

  lift(event) {
    if (this.panning?.taken || this.span) event.stopPropagation()
    this.panning = null
    // What's left of a pinch is one finger that should not start a pan.
    this.touches.clear()
    this.span = 0
    this.cursor()
  }

  spread() {
    const [ a, b ] = [ ...this.touches.values() ]
    return Math.hypot(a.x - b.x, a.y - b.y)
  }

  // On the wrapper, since a captured pointer takes its cursor from the
  // element that captured it, not from whatever is under it.
  cursor() {
    this.element.style.cursor = this.panning ? "grabbing" : this.view.w < this.base.w ? "grab" : ""
  }

  apply() {
    this.view.x = Math.min(Math.max(this.view.x, this.base.x), this.base.x + this.base.w - this.view.w)
    this.view.y = Math.min(Math.max(this.view.y, this.base.y), this.base.y + this.base.h - this.view.h)
    // Only once zoomed does a finger move the map; before that it scrolls the page.
    // A readout left where the map was would point at the wrong country.
    this.dispatch("move")
    this.element.style.touchAction = this.view.w < this.base.w ? "none" : ""
    if (this.hasInTarget) this.inTarget.disabled = this.view.w <= this.base.w / this.constructor.reach + 1e-6
    if (this.hasOutTarget) this.outTarget.disabled = this.view.w >= this.base.w - 1e-6
    this.svgTarget.setAttribute("viewBox", `${this.view.x} ${this.view.y} ${this.view.w} ${this.view.h}`)
    this.cursor()
  }
}
