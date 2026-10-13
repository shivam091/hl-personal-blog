import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

/*
  Redrawn in place, so picking weeks or months, or what's charted, doesn't
  jump back to the top.
*/
export default class extends Controller {
  static values = { param: { type: String, default: "chart_by" } }

  change() {
    const url = new URL(window.location.href)
    if (this.element.value) url.searchParams.set(this.paramValue, this.element.value)
    else url.searchParams.delete(this.paramValue)
    Turbo.visit(url.toString(), { action: "replace", refresh: { method: "morph", scroll: "preserve" } })
  }
}
