import { Controller } from "@hotwired/stimulus"

/*
  Not named *_controller, so it is never registered on its own.
*/
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
    Object.assign(tip.style, { left: `${left}px`, top: `${over < edge ? bottom + below : over}px` })
  }
}
