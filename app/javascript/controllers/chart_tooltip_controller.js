import { Controller } from "@hotwired/stimulus"

/*
  So a value on a dense chart can be read without counting gridlines.
  Readouts go in as text, since page names and countries come from stored
  data.
*/
export default class extends Controller {
  static targets = [ "hit", "tooltip", "crosshair" ]
  // Lines are 2px, too thin to hit exactly.
  static lineReach = 6
  // Copied from ChartsHelper::MARKERS, so a readout's key matches its legend.
  static markers = {
    circle: "M5 .5a4.5 4.5 0 1 1 0 9a4.5 4.5 0 1 1 0-9z", square: "M1 1h8v8H1z", diamond: "M5 0l5 5-5 5-5-5z",
    triangle_down: "M0 1h10L5 9.5z", triangle: "M5 .5L10 9H0z", drop: "M5 0C5 0 9 4.6 9 6.5a4 4 0 0 1-8 0C1 4.6 5 0 5 0z"
  }

  connect() {
    this.index = -1
    this.markers = []
  }

  /*
    Turbo caches the page as it is, and a readout left open would come back
    with it.
  */
  disconnect() {
    this.hide()
  }

  /*
    Looked up by position, since a touch keeps its first target for the
    whole drag and would otherwise never move off the day it started on.
  */
  point(event) {
    const under = document.elementFromPoint(event.clientX, event.clientY)
    const hit = under?.closest("[data-chart-tooltip-target~='hit']")
    if (!hit || !this.element.contains(hit)) return this.hide()

    this.index = this.hitTargets.indexOf(hit)
    this.show(hit, event.clientX, event.clientY, true)
  }

  /*
    A finger leaves the moment it lifts, so the readout stays until the
    next tap elsewhere.
  */
  leave(event) {
    if (event.pointerType !== "touch") this.hide()
  }

  /*
    The readout is fixed to the viewport, so once the page or a table under
    it scrolls it points at nothing; on touch, nothing else would close it.
  */
  scrolled() {
    if (this.active) this.hide()
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

  hide() {
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
      this.element.append(marker)
      this.markers.push(marker)
    })
    return frame.left + left
  }

  /*
    Values lead and names follow, since the reader already has the series
    and wants the number.
  */
  fill(tip) {
    const title = document.createElement("p")
    title.className = "mb-1 font-medium text-slate-500"
    title.textContent = tip.title

    const list = document.createElement("ul")
    list.className = "space-y-0.5"
    tip.rows.forEach((row, index) => {
      const item = document.createElement("li")
      item.className = "flex flex-wrap items-center gap-x-2"
      // Only a day's rows stand for series; other readouts' rows would be
      // faded by mistake.
      if (tip.x != null) item.dataset.series = index
      if (row.color) item.append(this.swatch(row))

      const value = document.createElement("strong")
      value.className = "shrink-0 font-semibold whitespace-nowrap tabular-nums text-slate-900"
      value.textContent = row.value
      item.append(value)

      if (row.name) {
        const name = document.createElement("span")
        // Wrapped rather than run past the box, since a name can be a
        // post's whole title.
        name.className = "min-w-0 break-words text-slate-600"
        name.textContent = row.name
        item.append(name)
      }
      // On its own line, so the figure and how it moved read apart.
      if (row.change) {
        const change = document.createElement("span")
        change.className = "basis-full pl-5 text-slate-500 tabular-nums"
        change.textContent = row.change
        item.append(change)
      }
      list.append(item)
    })
    this.tooltipTarget.replaceChildren(title, list, ...this.note(tip))
  }

  // Under the figures, since it's a caveat on every one of them.
  note(tip) {
    if (!tip.note) return []

    const note = document.createElement("p")
    note.className = "mt-1.5 border-t border-slate-200 pt-1.5 text-slate-500"
    note.textContent = tip.note
    return [ note ]
  }

  /*
    A short stroke rather than a box, matching how the lines are drawn; a
    charted row's shape where it has one, matching its legend.
  */
  swatch(row) {
    const shape = this.shape(row, false)
    if (shape) return shape

    const key = document.createElement("span")
    const broken = row.dashed || row.dotted
    key.className = broken ? `w-3 shrink-0 border-t-2 ${row.dotted ? "border-dotted" : "border-dashed"}` : "h-0.5 w-3 shrink-0"
    if (broken) key.style.borderColor = this.color(row.color)
    else key.style.backgroundColor = this.color(row.color)
    return key
  }

  /*
    Fixed to the viewport, so a card's rounded-corner clipping can't cut it
    off, and kept on screen near the edges.
  */
  place(clientX, clientY) {
    const tooltip = this.tooltipTarget
    tooltip.hidden = false
    const { width, height } = tooltip.getBoundingClientRect()
    const left = Math.min(Math.max(clientX - width / 2, 8), window.innerWidth - width - 8)
    const top = clientY - height - 12 < 8 ? clientY + 16 : clientY - height - 12
    Object.assign(tooltip.style, { left: `${left}px`, top: `${top}px` })
  }

  /*
    Drawn as ChartsHelper#marker_svg draws them, so the shape in a readout
    matches the mark on the chart.
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
