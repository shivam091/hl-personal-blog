import { Controller } from "@hotwired/stimulus"

/*
  Small countries are a few pixels wide, so the map can be zoomed and moved
  rather than only squinted at. Done by moving the viewBox, so the shapes stay
  sharp and the readout keeps finding them under the pointer.
*/
export default class extends Controller {
  static targets = [ "svg" ]
  static step = 1.6
  // Eight times in is as far as the shapes carry detail.
  static reach = 8

  connect() {
    const box = this.svgTarget.viewBox.baseVal
    this.base = { x: box.x, y: box.y, w: box.width, h: box.height }
    this.view = { ...this.base }
  }

  /*
    Toward the pointer, so what's under it stays put. Only with ctrl or cmd
    held, which is also how a trackpad pinch arrives, so the page itself can
    still be scrolled past the map.
  */
  wheel(event) {
    if (!event.ctrlKey && !event.metaKey) return

    event.preventDefault()
    this.zoom(Math.exp(event.deltaY * 0.01), event)
  }

  // Shift takes it back out.
  double(event) {
    this.zoom(event.shiftKey ? this.constructor.step : 1 / this.constructor.step, event)
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
    if (this.view.w >= this.base.w || event.button !== 0) return

    event.stopPropagation()
    this.panning = { x: event.clientX, y: event.clientY, view: { ...this.view } }
    this.cursor()
    this.element.setPointerCapture?.(event.pointerId)
  }

  drag(event) {
    if (!this.panning) return

    event.stopPropagation()
    const box = this.svgTarget.getBoundingClientRect()
    this.view.x = this.panning.view.x - (event.clientX - this.panning.x) / box.width * this.view.w
    this.view.y = this.panning.view.y - (event.clientY - this.panning.y) / box.height * this.view.h
    this.apply()
  }

  release(event) {
    if (!this.panning) return

    event.stopPropagation()
    this.panning = null
    this.cursor()
  }

  // An open hand once there's more map to move to, closed while it's held.
  // On the wrapper, since a captured pointer takes its cursor from the
  // element that captured it, not from whatever is under it.
  cursor() {
    this.element.style.cursor = this.panning ? "grabbing" : this.view.w < this.base.w ? "grab" : ""
  }

  apply() {
    this.view.x = Math.min(Math.max(this.view.x, this.base.x), this.base.x + this.base.w - this.view.w)
    this.view.y = Math.min(Math.max(this.view.y, this.base.y), this.base.y + this.base.h - this.view.h)
    this.svgTarget.setAttribute("viewBox", `${this.view.x} ${this.view.y} ${this.view.w} ${this.view.h}`)
    this.cursor()
  }
}
