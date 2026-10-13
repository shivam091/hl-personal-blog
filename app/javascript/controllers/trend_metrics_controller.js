import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

/*
  Redrawn in place, as a change of granularity is, so ticking a figure
  doesn't jump back to the top.
*/
export default class extends Controller {
  static targets = [ "box" ]

  change() {
    const url = new URL(window.location.href)
    url.searchParams.set("trend", this.boxTargets.filter((box) => box.checked).map((box) => box.value).join(","))
    Turbo.visit(url.toString(), { action: "replace", refresh: { method: "morph", scroll: "preserve" } })
  }
}
