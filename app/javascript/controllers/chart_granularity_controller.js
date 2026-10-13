import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static values = { param: { type: String, default: "by" } }

  change() {
    const url = new URL(window.location.href)
    if (this.element.value) url.searchParams.set(this.paramValue, this.element.value)
    else url.searchParams.delete(this.paramValue)
    Turbo.visit(url.toString(), { action: "replace", refresh: { method: "morph", scroll: "preserve" } })
  }
}
