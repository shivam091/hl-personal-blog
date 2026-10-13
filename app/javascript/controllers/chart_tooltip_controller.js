import TooltipBase from "controllers/tooltip_base"
import { Turbo } from "@hotwired/turbo-rails"

/*
  So a value on a dense chart can be read without counting gridlines.
  Readouts go in as text, since page names and countries come from stored
  data.
*/
export default class extends TooltipBase {
  static targets = [ "hit", "tooltip", "crosshair" ]
  // Lines are 2px, too thin to hit exactly.
  static lineReach = 6
  // Long enough that a tap or the start of a scroll never counts as a hold.
  static holdFor = 350
  static holdSlop = 10
  // So a readout's key matches its legend.
  static earlierOpacity = 0.6

  static markers = {
    circle: "M5 .5a4.5 4.5 0 1 1 0 9a4.5 4.5 0 1 1 0-9z", square: "M1 1h8v8H1z", diamond: "M5 0l5 5-5 5-5-5z",
    triangle_down: "M0 1h10L5 9.5z", triangle: "M5 .5L10 9H0z", drop: "M5 0C5 0 9 4.6 9 6.5a4 4 0 0 1-8 0C1 4.6 5 0 5 0z"
  }

  connect() {
    super.connect()
    this.index = -1
    this.markers = []
    this.pinned = null
    this.gesture = null
    this.release = (event) => this.finish(event)
    this.abort = () => this.cancel()
    // A long press would otherwise open the browser's own menu mid-selection.
    this.menu = (event) => { if (this.gesture || this.hold) event.preventDefault() }
    this.element.addEventListener("contextmenu", this.menu)
    this.moved = () => { this.cancel(); this.hide() }
    this.element.addEventListener("map-zoom:move", this.moved)
    this.outside = (event) => { if (this.pinned && !this.element.contains(event.target)) this.hide() }
    document.addEventListener("pointerdown", this.outside)
  }

  disconnect() {
    document.removeEventListener("pointerdown", this.outside)
    document.removeEventListener("pointerup", this.release)
    document.removeEventListener("pointercancel", this.abort)
    this.element.removeEventListener("contextmenu", this.menu)
    this.element.removeEventListener("map-zoom:move", this.moved)
    this.cancel()
    super.disconnect()
  }

  /*
    Looked up by position, since a touch keeps its first target for the
    whole drag and would otherwise never move off the day it started on.
  */
  point(event) {
    if (event.type === "pointerdown" && event.pointerType === "mouse") return this.begin(event)
    if (this.gesture) return this.stretch(event)
    if (this.pinned) return
    if (this.hold && event.type === "pointermove") this.steady(event)

    const hit = this.hitAt(event.clientX, event.clientY)
    if (!hit) return this.hide()

    if (event.type === "pointerdown" && event.pointerType === "touch") {
      const href = hit === this.active && JSON.parse(hit.dataset.tip).href
      if (href) return Turbo.visit(href)

      this.arm(event, hit)
    }

    this.index = this.hitTargets.indexOf(hit)
    this.show(hit, event.clientX, event.clientY, true)
  }

  hitAt(clientX, clientY) {
    const hit = document.elementFromPoint(clientX, clientY)?.closest("[data-chart-tooltip-target~='hit']")
    return hit && this.element.contains(hit) ? hit : null
  }

  /*
    Which of a click and a drag a press is only shows once the pointer moves,
    so neither can be acted on at the press.
  */
  begin(event) {
    if (event.button !== 0) return

    const hit = this.hitAt(event.clientX, event.clientY)
    if (!hit) return this.hide()

    this.gesture = { hit, x: event.clientX, y: event.clientY, moved: false }
    document.addEventListener("pointerup", this.release, { once: true })
  }

  /*
    A finger can't tell a drag across days from a scrub to read them, so a
    zoom starts with a hold, as a mouse's starts with a press.
  */
  arm(event, hit) {
    this.cancel()
    const { clientX: x, clientY: y } = event
    this.hold = {
      x, y, timer: setTimeout(() => {
        this.hold = null
        this.gesture = { hit, x, y, moved: false, touch: true }
        this.element.style.userSelect = "none"
        navigator.vibrate?.(10)
      }, this.constructor.holdFor)
    }
    // From the press, since a tap that lifts before the hold completes must
    // end it, or the hold would start with no finger down and take the next tap.
    document.addEventListener("pointerup", this.release, { once: true })
    document.addEventListener("pointercancel", this.abort, { once: true })
  }

  steady(event) {
    const slop = this.constructor.holdSlop
    if (Math.hypot(event.clientX - this.hold.x, event.clientY - this.hold.y) > slop) this.cancel()
  }

  cancel() {
    if (this.hold) clearTimeout(this.hold.timer)
    this.hold = null
    document.removeEventListener("pointerup", this.release)
    document.removeEventListener("pointercancel", this.abort)
    if (!this.gesture) return

    this.gesture = null
    this.band?.remove()
    this.band = null
    this.element.style.userSelect = ""
  }

  stretch(event) {
    const gesture = this.gesture
    if (!gesture.moved && Math.abs(event.clientX - gesture.x) < 6) return

    gesture.moved = true
    this.hide()
    const svg = gesture.hit.ownerSVGElement
    if (!svg || !this.zoomKey(gesture.hit)) return

    this.element.style.userSelect = "none"
    this.band ??= this.makeBand()
    const frame = this.element.getBoundingClientRect()
    const box = svg.getBoundingClientRect()
    const from = Math.min(gesture.x, event.clientX)
    const to = Math.max(gesture.x, event.clientX)
    Object.assign(this.band.style, {
      left: `${Math.max(from, box.left) - frame.left}px`, width: `${Math.min(to, box.right) - Math.max(from, box.left)}px`,
      top: `${box.top - frame.top}px`, height: `${box.height}px`
    })
  }

  makeBand() {
    const band = document.createElement("span")
    band.className = "pointer-events-none absolute z-10 rounded-sm bg-slate-900/10 ring-1 ring-slate-400"
    this.element.append(band)
    return band
  }

  finish(event) {
    if (this.hold) clearTimeout(this.hold.timer)
    this.hold = null
    document.removeEventListener("pointercancel", this.abort)
    const gesture = this.gesture
    this.gesture = null
    this.band?.remove()
    this.band = null
    this.element.style.userSelect = ""
    if (!gesture) return

    // A hold that never moved has nothing to zoom to; its readout stays.
    if (gesture.touch && !gesture.moved) return

    const last = gesture.moved ? this.nearestHit(event.clientX) : null
    const first = this.zoomKey(gesture.hit)
    const second = last && this.zoomKey(last)
    if (first && second && first !== second) return this.zoom(first, second)

    const href = JSON.parse(gesture.hit.dataset.tip).href
    if (href && !gesture.moved) return Turbo.visit(href)

    this.click(gesture.hit, event)
  }

  // By position along the chart, so a drag that ends above or below the plot
  // still lands on a day.
  nearestHit(clientX) {
    let best = null
    let gap = Infinity
    this.hitTargets.forEach((hit) => {
      const box = hit.getBoundingClientRect()
      const away = Math.abs(box.left + box.width / 2 - clientX)
      if (away < gap) [ best, gap ] = [ hit, away ]
    })
    return best
  }

  zoomKey(hit) {
    return JSON.parse(hit.dataset.tip).key
  }

  zoom(first, second) {
    const [ from, to ] = [ first, second ].sort()
    const url = new URL(window.location.href)
    url.searchParams.set("from", from)
    url.searchParams.set("to", to)
    url.searchParams.delete("page")
    Turbo.visit(url.toString())
  }

  click(hit, event) {
    const release = this.pinned === hit
    this.index = this.hitTargets.indexOf(hit)
    this.show(hit, event.clientX, event.clientY, true)
    if (release) return

    this.pinned = hit
    this.tooltipTarget.classList.add("ring-2", "ring-slate-400")
  }

  /*
    A finger leaves the moment it lifts, so the readout stays until the
    next tap elsewhere.
  */
  leave(event) {
    if (event.pointerType !== "touch" && !this.pinned) this.hide()
  }

  /*
    Only for the keyboard: a tap focuses the chart too, and would open the
    first day instead of the one tapped.
  */
  focus() {
    if (this.element.matches(":focus-visible")) this.showAt(Math.max(this.index, 0))
  }

  key(event) {
    const steps = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }
    const last = this.hitTargets.length - 1
    if (event.key === "Escape") return this.hide()

    if (event.key === "Home") this.index = 0
    else if (event.key === "End") this.index = last
    else if (event.key in steps) this.index = Math.min(Math.max(this.index + steps[event.key], 0), last)
    else return

    event.preventDefault()
    this.showAt(this.index)
  }

  get open() {
    return !!this.active
  }

  hide() {
    this.pinned = null
    this.tooltipTarget.classList.remove("ring-2", "ring-slate-400")
    this.tooltipTarget.hidden = true
    if (this.hasCrosshairTarget) this.crosshairTarget.hidden = true
    this.markers.forEach((marker) => marker.remove())
    this.markers = []
    if (this.active) this.dispatch("hide")
    this.active?.removeAttribute("data-active")
    this.active = null
  }

  showAt(index) {
    const hit = this.hitTargets[index]
    if (!hit) return

    const box = hit.getBoundingClientRect()
    this.show(hit, box.left + box.width / 2, box.top)
  }

  show(hit, clientX, clientY, pointer = false) {
    const tip = JSON.parse(hit.dataset.tip)
    const series = hit.dataset.series ?? (pointer ? this.nearest(hit, tip, clientX, clientY) : null)
    this.hide()
    this.active = hit
    hit.setAttribute("data-active", "")
    if (tip.x != null && hit.ownerSVGElement) clientX = this.trace(hit.ownerSVGElement, tip)
    this.fill(tip)
    this.place(clientX, clientY)
    this.dispatch("show", { detail: { series } })
  }

  /*
    So a chart that picks out one series picks out the one pointed at, and
    none over empty space. Measured between days too, since a steep line
    runs far from its day's point.
  */
  nearest(hit, tip, clientX, clientY) {
    const svg = hit.ownerSVGElement
    if (!svg || tip.x == null) return null

    const box = svg.getBoundingClientRect()
    const view = svg.viewBox.baseVal
    const x = ((clientX - box.left) / box.width) * view.width
    const y = ((clientY - box.top) / box.height) * view.height
    const index = this.hitTargets.indexOf(hit)
    const next = this.hitTargets[x >= tip.x ? index + 1 : index - 1]
    const other = next && JSON.parse(next.dataset.tip)
    const along = other?.x != null && other.x !== tip.x ? (x - tip.x) / (other.x - tip.x) : 0

    let best = null
    let distance = Infinity
    tip.rows.forEach((row, series) => {
      if (row.y == null) return
      const end = other?.rows[series]?.y
      const lineY = end == null ? row.y : row.y + (end - row.y) * along
      const gap = (Math.abs(lineY - y) / view.height) * box.height
      if (gap < distance) [ best, distance ] = [ series, gap ]
    })
    return distance <= this.constructor.lineReach ? best : null
  }

  /*
    Snaps to the day rather than the pointer, and marks every series there,
    so the reader aims at a date, never at a 2px line.
  */
  trace(svg, tip) {
    const frame = this.element.getBoundingClientRect()
    const box = svg.getBoundingClientRect()
    const view = svg.viewBox.baseVal
    const left = box.left - frame.left + (tip.x / view.width) * box.width

    if (this.hasCrosshairTarget) {
      Object.assign(this.crosshairTarget.style, { left: `${left}px`, top: `${box.top - frame.top}px`, height: `${box.height}px` })
      this.crosshairTarget.hidden = false
    }
    tip.rows.filter((row) => row.y != null).forEach((row) => {
      const shape = this.shape(row, true)
      const marker = document.createElement("span")
      marker.className = shape ? "pointer-events-none absolute flex -translate-x-1/2 -translate-y-1/2" :
        "pointer-events-none absolute size-2 -translate-x-1/2 -translate-y-1/2 rounded-full ring-2 ring-white"
      if (shape) marker.append(shape)
      Object.assign(marker.style, {
        left: `${left}px`, top: `${box.top - frame.top + (row.y / view.height) * box.height}px`, backgroundColor: shape ? "" : this.color(row.color)
      })
      if (row.earlier) marker.style.opacity = this.constructor.earlierOpacity
      this.element.append(marker)
      this.markers.push(marker)
    })
    return frame.left + left
  }

  /*
    Name first and the figure after it, so a figure is never read without
    what it counts, nor a compared one without the day it is for.
  */
  fill(tip) {
    const title = document.createElement("p")
    title.className = "mb-1 font-medium text-slate-500"
    title.textContent = tip.title

    const list = document.createElement("ul")
    list.className = "space-y-1"
    // With no swatch in any row, the empty column would indent the names
    // from the title.
    const keyed = tip.rows.some((row) => row.color)
    tip.rows.forEach((row, index) => {
      const item = document.createElement("li")
      item.className = `grid ${keyed ? "grid-cols-[0.75rem_minmax(min-content,1fr)_auto]" : "grid-cols-[minmax(min-content,1fr)_auto]"} items-baseline gap-x-2`
      // Only a day's rows stand for series; other readouts' rows would be
      // faded by mistake.
      if (tip.x != null) item.dataset.series = index
      const key = row.color ? this.swatch(row) : document.createElement("span")
      if (row.earlier) key.style.opacity = this.constructor.earlierOpacity
      // Level with the first line, so a name or figure that wraps leaves it
      // at the top rather than in the middle.
      key.classList.add("self-start", row.marker ? "mt-[3px]" : "mt-[7px]")

      // Wrapped rather than run past the box, since a name can be a post's
      // whole title.
      const name = document.createElement("span")
      name.className = "min-w-0 break-words text-slate-600"
      name.textContent = row.name ?? ""

      const value = document.createElement("strong")
      value.className = "max-w-48 break-words text-right font-semibold tabular-nums text-slate-900"
      value.textContent = row.value
      item.append(...(keyed ? [key, name, value] : [name, value]))

      // On a line of its own under the name, so a long range never wraps
      // the name; the change sits beside it, under the figure.
      if (row.period || row.change) {
        const period = document.createElement("span")
        period.className = `${keyed ? "col-start-2" : "col-start-1"} text-[11px] whitespace-nowrap text-slate-500`
        period.textContent = row.period ?? ""
        item.append(period)
      }
      if (row.change) {
        const change = document.createElement("span")
        const tone = row.tone > 0 ? "text-green-600" : row.tone < 0 ? "text-red-600" : "text-slate-500"
        change.className = `text-right text-xs font-medium tabular-nums ${tone}`
        change.textContent = row.change
        item.append(change)
      }
      list.append(item)
    })
    this.tooltipTarget.replaceChildren(title, list, ...this.note(tip))
  }

  // Under the figures, since it's a caveat on every one of them.
  note(tip) {
    const notes = []
    if (tip.note) {
      const note = document.createElement("p")
      note.className = "mt-1.5 border-t border-slate-200 pt-1.5 text-slate-500"
      note.textContent = tip.note
      notes.push(note)
    }
    const touch = window.matchMedia("(pointer: coarse)").matches
    const advice = tip.href ? (touch ? "Tap again to open" : "Click to open") :
      tip.key ? (touch ? "Hold, then drag to zoom" : "Drag to zoom · click to hold") : null
    if (advice) {
      const hint = document.createElement("p")
      hint.className = "mt-1.5 text-[11px] text-slate-400"
      hint.textContent = advice
      notes.push(hint)
    }
    return notes
  }

  /*
    A short stroke rather than a box, matching how the lines are drawn; a
    charted row's shape where it has one, matching its legend.
  */
  swatch(row) {
    const shape = this.shape(row, false)
    if (shape) return shape

    const broken = row.dashed || row.dotted
    if (!broken) {
      const key = document.createElement("span")
      key.className = "h-0.5 w-3 shrink-0"
      key.style.backgroundColor = this.color(row.color)
      return key
    }

    // Stroked as the chart strokes its line, so the dashes match it and its
    // legend rather than a border's own.
    const ns = "http://www.w3.org/2000/svg"
    const svg = document.createElementNS(ns, "svg")
    for (const [name, value] of Object.entries({ width: 12, height: 2, class: "shrink-0 overflow-visible", "aria-hidden": "true" })) {
      svg.setAttribute(name, value)
    }
    const line = document.createElementNS(ns, "line")
    for (const [name, value] of Object.entries({ x1: row.dotted ? 1 : 0, x2: row.dotted ? 11 : 12, y1: 1, y2: 1, stroke: this.color(row.color), "stroke-width": 2,
      "stroke-dasharray": row.dotted ? "0 4" : "4 3", "stroke-linecap": row.dotted ? "round" : "butt" })) {
      line.setAttribute(name, value)
    }
    svg.append(line)
    return svg
  }

  place(clientX, clientY) {
    this.tooltipTarget.hidden = false
    this.placeNear(this.tooltipTarget, { x: clientX, top: clientY })
  }

  /*
    So the shape in a readout matches the mark on the chart.
  */
  shape(row, outline) {
    const path = this.constructor.markers[row.marker]
    if (!path) return null

    const ns = "http://www.w3.org/2000/svg"
    const svg = document.createElementNS(ns, "svg")
    for (const [name, value] of Object.entries({ width: 10, height: 10, viewBox: "-1 -1 12 12", class: "shrink-0 overflow-visible", "aria-hidden": "true" })) {
      svg.setAttribute(name, value)
    }
    const shape = document.createElementNS(ns, "path")
    shape.setAttribute("d", path)
    shape.setAttribute("fill", this.color(row.color))
    if (outline) {
      shape.setAttribute("stroke", "#fff")
      shape.setAttribute("stroke-width", "2")
      shape.setAttribute("paint-order", "stroke")
    }
    svg.append(shape)
    return svg
  }

  // So markup can't put anything but a colour into a style.
  color(value) {
    return /^#[0-9a-f]{6}$/i.test(value || "") ? value : "#475569"
  }
}
