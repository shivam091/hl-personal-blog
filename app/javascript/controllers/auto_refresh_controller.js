import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

/*
  Paused while the tab is hidden, since each refresh spends API quota nobody
  is reading.
*/
export default class extends Controller {
  static values = { interval: { type: Number, default: 60 } }

  connect() {
    this.refreshedAt = Date.now()
    this.onVisibility = () => this.schedule()
    document.addEventListener("visibilitychange", this.onVisibility)
    this.schedule()
  }

  disconnect() {
    clearTimeout(this.timer)
    document.removeEventListener("visibilitychange", this.onVisibility)
  }

  schedule() {
    clearTimeout(this.timer)
    if (document.hidden) return

    const wait = Math.max(this.intervalValue * 1000 - (Date.now() - this.refreshedAt), 0)
    this.timer = setTimeout(() => this.refresh(), wait)
  }

  // Rescheduled here, since a morph keeps this element and won't reconnect it.
  refresh() {
    this.refreshedAt = Date.now()
    Turbo.visit(window.location.href, { action: "replace", refresh: { method: "morph", scroll: "preserve" } })
    this.schedule()
  }
}
