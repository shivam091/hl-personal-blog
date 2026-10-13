import { Controller } from "@hotwired/stimulus"

/*
  Six lines on one axis tangle, so some can be picked out and the rest
  fade, in the bars beside them too. Each pick adds to the others, so two
  rows can be read against each other; pointing at one shows it beside them.
*/
export default class extends Controller {
  static targets = [ "toggle" ]

  connect() {
    this.selected = new Set()
    this.hovered = null
  }

  toggle(event) {
    const series = event.currentTarget.dataset.series
    if (!this.selected.delete(series)) this.selected.add(series)
    this.apply()
  }

  preview(event) {
    this.hovered = event.currentTarget.dataset.series
    this.apply()
  }

  // The readout's rows are drawn fresh each time, so they're faded here too.
  near(event) {
    this.hovered = event.detail.series == null ? null : String(event.detail.series)
    this.apply()
  }

  restore() {
    this.hovered = null
    this.apply()
  }

  apply() {
    const picked = this.hovered == null ? this.selected : new Set([ ...this.selected, this.hovered ])
    this.element.querySelectorAll("[data-series]").forEach((element) => {
      // So a legend pick never hides the day's other figures; only pointing at a line does.
      const reading = element.closest("[data-chart-tooltip-target='tooltip']") ? new Set(this.hovered == null ? [] : [ this.hovered ]) : picked
      const on = reading.has(element.dataset.series)
      element.style.opacity = reading.size === 0 || on ? "" : "0.25"
      if (element.dataset.seriesLine != null) element.style.strokeWidth = on ? "3" : ""
      if (element.dataset.seriesArc != null) element.style.strokeWidth = on && reading.size > 0 ? "20" : ""
    })
    this.toggleTargets.forEach((toggle) => {
      toggle.setAttribute("aria-pressed", String(this.selected.has(toggle.dataset.series)))
    })
  }
}
