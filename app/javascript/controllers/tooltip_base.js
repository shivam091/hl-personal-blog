import { Controller } from "@hotwired/stimulus"

/*
  Not named *_controller, so it is never registered on its own.
*/
let ringCount = 0

export default class extends Controller {
  static edge = 8

  /*
    A scroll closes it, since a viewport-fixed tooltip would otherwise point
    at nothing and, on touch, nothing else would.
  */
  connect() {
    this.dismiss = () => { if (this.open) this.hide() }
    document.addEventListener("scroll", this.dismiss, { capture: true, passive: true })
    document.addEventListener("turbo:before-cache", this.dismiss)
  }

  /*
    Turbo caches the page as it is, and a tooltip left open would come back
    with it.
  */
  disconnect() {
    document.removeEventListener("scroll", this.dismiss, { capture: true })
    document.removeEventListener("turbo:before-cache", this.dismiss)
    this.hide()
  }

  /*
    Fixed to the viewport, so a card's rounded-corner clipping can't cut it
    off. Above the anchor unless there's no room, and kept on screen near the
    edges.
  */
  placeNear(tip, { x, top, bottom = top, above = 12, below = 16 }) {
    const { edge } = this.constructor
    const { width, height } = tip.getBoundingClientRect()
    const left = Math.min(Math.max(x - width / 2, edge), window.innerWidth - width - edge)
    const over = top - height - above
    const higher = over >= edge
    Object.assign(tip.style, { left: `${left}px`, top: `${higher ? over : bottom + below}px` })
    this.pointAt(tip, x - left, higher, width)
  }

  /*
    A ring is a shadow on the box, which the arrow doesn't carry, so a held
    readout would show a ring that breaks where its arrow starts. The ring's
    colour is drawn along the arrow's curve, under its fill, so only the
    outer half shows, as the ring does outside the border.
  */
  ringArrow(tip) {
    const arrow = tip.querySelector("[data-tooltip-arrow]")
    if (!arrow) return

    arrow.querySelector("[data-tooltip-ring]")?.remove()
    const ring = document.createElementNS("http://www.w3.org/2000/svg", "path")
    ring.setAttribute("d", arrow.children[1].getAttribute("d"))
    ring.setAttribute("fill", "none")
    ring.setAttribute("stroke", getComputedStyle(tip).getPropertyValue("--tw-ring-color") || "#94a3b8")
    ring.setAttribute("stroke-width", "5")
    ring.setAttribute("data-tooltip-ring", "")
    // Square ends of a thick stroke would stick up into the box beside the
    // arrow's base, so nothing above the base is drawn.
    const ns = "http://www.w3.org/2000/svg"
    const clip = document.createElementNS(ns, "clipPath")
    const id = `tooltip-ring-${++ringCount}`
    clip.id = id
    const cut = document.createElementNS(ns, "rect")
    for (const [ name, value ] of Object.entries({ x: -4, y: 0, width: 22, height: 12 })) cut.setAttribute(name, value)
    clip.append(cut)
    ring.setAttribute("clip-path", `url(#${id})`)
    arrow.prepend(clip, ring)
  }

  /*
    Kept on the anchor rather than the middle, since the box is shifted to
    stay on screen. Drawn as the box is, from its own colours, so one shape
    serves a light readout with a border and a dark one with none; the strip
    above the curve covers the border where the two meet.
  */
  pointAt(tip, x, higher, width) {
    const { backgroundColor, borderTopColor, borderTopWidth } = getComputedStyle(tip)
    const ns = "http://www.w3.org/2000/svg"
    let arrow = tip.querySelector("[data-tooltip-arrow]")
    if (!arrow) {
      arrow = document.createElementNS(ns, "svg")
      for (const [name, value] of Object.entries({ width: 14, height: 8, viewBox: "0 0 14 8", "aria-hidden": "true", "data-tooltip-arrow": "" })) {
        arrow.setAttribute(name, value)
      }
      const fill = document.createElementNS(ns, "path")
      fill.setAttribute("d", "M0 1C3.5 1 5.25 7 7 7S10.5 1 14 1V0H0Z")
      const edge = document.createElementNS(ns, "path")
      edge.setAttribute("d", "M0 1C3.5 1 5.25 7 7 7S10.5 1 14 1")
      edge.setAttribute("fill", "none")
      arrow.append(fill, edge)
      tip.append(arrow)
    }
    const [ fill, edge ] = arrow.children
    fill.setAttribute("fill", backgroundColor)
    edge.setAttribute("stroke", parseFloat(borderTopWidth) > 0 ? borderTopColor : "none")
    Object.assign(arrow.style, {
      position: "absolute", pointerEvents: "none", overflow: "visible",
      left: `${Math.min(Math.max(x, 12), width - 12) - 7}px`,
      top: higher ? "100%" : "auto", bottom: higher ? "auto" : "100%",
      transform: higher ? "none" : "scaleY(-1)"
    })
  }
}
