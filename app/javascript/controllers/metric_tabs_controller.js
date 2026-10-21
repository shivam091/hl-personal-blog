import { Controller } from "@hotwired/stimulus"

/*
  Every figure's chart is already on the page, so a tab is switched without
  a visit; the URL still follows, so a reload or a shared link opens on it.
*/
export default class extends Controller {
  static targets = [ "tab", "panel" ]
  // Blank for tabs not worth a link, such as a list's Top and Trending.
  static values = { param: { type: String, default: "trend" } }

  select(event) {
    this.show(this.tabTargets.indexOf(event.currentTarget))
  }

  // Arrows move between tabs as in any tab list, so the keyboard needs one
  // stop for the row rather than four.
  key(event) {
    const steps = { ArrowRight: 1, ArrowLeft: -1 }
    const current = this.tabTargets.findIndex((tab) => tab.getAttribute("aria-selected") === "true")
    const last = this.tabTargets.length - 1
    let index
    if (event.key === "Home") index = 0
    else if (event.key === "End") index = last
    else if (event.key in steps) index = (current + steps[event.key] + this.tabTargets.length) % this.tabTargets.length
    else return

    event.preventDefault()
    this.show(index)
    this.tabTargets[index].focus()
  }

  show(index) {
    this.tabTargets.forEach((tab, i) => {
      tab.setAttribute("aria-selected", String(i === index))
      tab.tabIndex = i === index ? 0 : -1
    })
    this.panelTargets.forEach((panel, i) => { panel.hidden = i !== index })

    if (!this.paramValue) return

    const url = new URL(window.location.href)
    if (index === 0) url.searchParams.delete(this.paramValue)
    else url.searchParams.set(this.paramValue, this.tabTargets[index].dataset.field)
    window.history.replaceState(window.history.state, "", url)
  }
}
