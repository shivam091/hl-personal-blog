import { Controller } from "@hotwired/stimulus"

/*
  Six lines on one axis tangle, so one can be picked out and the rest fade,
  in the bars beside it too.
*/
export default class extends Controller {
  static targets = [ "toggle" ]

  connect() {
    this.selected = null
    this.hovered = null
  }

  toggle(event) {
    const series = event.currentTarget.dataset.series
    this.selected = this.selected === series ? null : series
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
    const active = this.hovered ?? this.selected
    this.element.querySelectorAll("[data-series]").forEach((element) => {
      // So a legend pick never hides the day's other figures; only pointing at a line does.
      const reading = element.closest("[data-chart-tooltip-target='tooltip']") ? this.hovered : active
      const on = reading === element.dataset.series
      element.style.opacity = reading == null || on ? "" : "0.25"
      if (element.dataset.seriesLine != null) element.style.strokeWidth = on ? "3" : ""
    })
    this.toggleTargets.forEach((toggle) => {
      toggle.setAttribute("aria-pressed", String(this.selected === toggle.dataset.series))
    })
  }
}
