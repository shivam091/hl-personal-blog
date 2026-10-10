import { Controller } from "@hotwired/stimulus"

/*
  A title only shows on hover, and a touch screen has none, so a change's
  comparison, or any other note kept in one, would never be read there. A tap
  on a plain element with a title shows it instead; links and buttons keep
  their own taps.
*/
export default class extends Controller {
  static interactive = "a, button, input, select, textarea, label, summary"

  connect() {
    this.touch = window.matchMedia("(hover: none)")
    this.close = () => this.hide()
    document.addEventListener("scroll", this.close, { capture: true, passive: true })
    document.addEventListener("turbo:before-cache", this.close)
  }

  disconnect() {
    document.removeEventListener("scroll", this.close, { capture: true })
    document.removeEventListener("turbo:before-cache", this.close)
    this.hide()
  }

  show(event) {
    if (!this.touch.matches) return

    const target = event.target.closest?.("[title]")
    const same = target && target === this.source
    this.hide()
    if (!target || same || event.target.closest(this.constructor.interactive)) return

    this.open(target)
  }

  open(target) {
    const text = target.getAttribute("title")
    if (!text) return

    // Taken off while shown, so the browser's own long-press bubble doesn't
    // appear over this one.
    this.source = target
    target.dataset.titleTip = text
    target.removeAttribute("title")

    const tip = document.createElement("div")
    tip.setAttribute("role", "tooltip")
    tip.className = "pointer-events-none fixed z-50 max-w-64 rounded-md bg-slate-900 px-3 py-2 text-xs leading-snug font-normal text-white shadow-lg"
    tip.textContent = text
    document.body.append(tip)

    const box = target.getBoundingClientRect()
    const { width, height } = tip.getBoundingClientRect()
    const left = Math.min(Math.max(box.left + box.width / 2 - width / 2, 8), window.innerWidth - width - 8)
    const above = box.top - height - 8
    Object.assign(tip.style, { left: `${left}px`, top: `${above < 8 ? box.bottom + 8 : above}px` })
    this.tip = tip
  }

  hide() {
    this.tip?.remove()
    this.tip = null
    if (this.source) {
      this.source.setAttribute("title", this.source.dataset.titleTip)
      delete this.source.dataset.titleTip
      this.source = null
    }
  }
}
