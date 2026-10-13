import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = [ "box" ]

  change() {
    const url = new URL(window.location.href)
    url.searchParams.set("trend", this.boxTargets.filter((box) => box.checked).map((box) => box.value).join(","))
    Turbo.visit(url.toString(), { action: "replace", refresh: { method: "morph", scroll: "preserve" } })
  }
}
