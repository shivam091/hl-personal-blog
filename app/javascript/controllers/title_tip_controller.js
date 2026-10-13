import TooltipBase from "controllers/tooltip_base"

/*
  A title only shows on hover, and a touch screen has none, so a change's
  comparison, or any other note kept in one, would never be read there. A tap
  on a plain element with a title shows it instead; links and buttons keep
  their own taps.
*/
export default class extends TooltipBase {
  static interactive = "a, button, input, select, textarea, label, summary"

  connect() {
    super.connect()
    this.touch = window.matchMedia("(hover: none)")
  }

  get open() {
    return !!this.tip
  }

  show(event) {
    if (!this.touch.matches) return

    const target = event.target.closest?.("[title]")
    const same = target && target === this.source
    // A chart's own readout already shows the full name, so a second bubble would repeat it.
    const inChart = target?.closest("[data-chart-tooltip-target~='hit']")
    this.hide()
    if (!target || inChart || same || event.target.closest(this.constructor.interactive)) return

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
    this.placeNear(tip, { x: box.left + box.width / 2, top: box.top, bottom: box.bottom, above: 8, below: 8 })
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
