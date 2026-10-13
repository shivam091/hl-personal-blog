import { Controller } from "@hotwired/stimulus"

// A copy shows nothing of its own, so the button's label says it worked.
export default class extends Controller {
  static values = { text: String }

  async copy() {
    try {
      await navigator.clipboard.writeText(this.textValue)
      this.flash("Copied")
    } catch {
      this.flash("Couldn't copy")
    }
  }

  flash(message) {
    this.label ??= this.element.getAttribute("aria-label")
    this.element.setAttribute("aria-label", message)
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.element.setAttribute("aria-label", this.label), 1500)
  }

  // Turbo caches the page as it is, and "Copied" would come back with it.
  disconnect() {
    clearTimeout(this.timer)
    if (this.label) this.element.setAttribute("aria-label", this.label)
  }
}
