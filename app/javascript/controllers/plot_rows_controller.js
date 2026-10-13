import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

/*
  Rows charted from other pages stay charted, since only this page's rows
  can be unticked here. Redrawn in place, so the table doesn't jump back to
  the top.
*/
export default class extends Controller {
  static targets = [ "row", "total", "all" ]
  static values = { plotted: Array, limit: Number }

  connect() {
    this.sync()
  }

  change() {
    this.sync()
    this.plot()
  }

  // Never ticks every row, since only so many lines can be told apart.
  toggleAll() {
    const any = this.rowTargets.some((row) => row.checked)
    this.rowTargets.forEach((row, index) => { row.checked = !any && index < this.limitValue })
    this.change()
  }

  sync() {
    const full = this.selection().length >= this.limitValue
    this.rowTargets.forEach((row) => {
      row.disabled = full && !row.checked
      row.title = row.disabled ? `Up to ${this.limitValue} rows can be charted` : ""
    })
    const ticked = this.rowTargets.filter((row) => row.checked).length
    if (this.hasAllTarget) {
      this.allTarget.checked = ticked > 0
      this.allTarget.indeterminate = ticked > 0 && ticked < Math.min(this.rowTargets.length, this.limitValue)
    }
  }

  selection() {
    const here = new Set(this.rowTargets.map((row) => this.key(row)))
    const elsewhere = this.plottedValue.map((values) => JSON.stringify(values)).filter((value) => !here.has(value))
    const ticked = this.rowTargets.filter((row) => row.checked).map((row) => this.key(row))
    return [ ...elsewhere, ...ticked ].slice(0, this.limitValue)
  }

  // Re-encoded, so a row matches its charted entry however the server escaped it.
  key(row) {
    return JSON.stringify(JSON.parse(row.value))
  }

  plot() {
    const url = new URL(window.location.href)
    url.searchParams.set("plot", `[${this.selection().join(",")}]`)
    if (this.hasTotalTarget && !this.totalTarget.checked) url.searchParams.set("plot_total", "0")
    else url.searchParams.delete("plot_total")
    Turbo.visit(url.toString(), { action: "replace", refresh: { method: "morph", scroll: "preserve" } })
  }
}
