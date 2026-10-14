import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "zone", "status" ]

  // Browsers can restore a form's state on Back, so start from the page.
  connect() {
    this.sync()
  }

  dragStart(event) {
    this.dragged = event.currentTarget
    event.dataTransfer.effectAllowed = "move"
    // Firefox starts no drag without data.
    event.dataTransfer.setData("text/plain", this.dragged.dataset.column)
    // A frame later, so the drag image is taken before the row fades.
    requestAnimationFrame(() => this.dragged?.setAttribute("data-dragging", ""))
  }

  dragOver(event) {
    const zone = event.currentTarget
    if (!this.dragged || !this.#accepts(zone, this.dragged)) return

    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    zone.insertBefore(this.dragged, this.#itemBelow(zone, event.clientY) ?? this.#placeholder(zone))
  }

  // The row is already in place; this only stops Firefox opening the data.
  drop(event) {
    event.preventDefault()
  }

  dragEnd() {
    const moved = this.dragged
    this.dragged = null
    moved?.removeAttribute("data-dragging")
    this.sync()
    if (moved) this.#announce(moved)
  }

  moveUp(event) {
    this.#step(event.currentTarget, -1)
  }

  moveDown(event) {
    this.#step(event.currentTarget, 1)
  }

  toggle(event) {
    const button = event.currentTarget
    const item = button.closest("[data-column]")
    const zone = this.zoneTargets.find(candidate => candidate !== item.parentElement)
    if (!this.#accepts(zone, item)) return

    zone.insertBefore(item, this.#placeholder(zone))
    this.sync()
    // Moving a row blurs it, which would drop keyboard users to the page.
    button.focus()
    this.#announce(item)
  }

  sync() {
    this.zoneTargets.forEach(zone => {
      const items = this.#items(zone)
      items.forEach((item, index) => {
        item.querySelector("input[type=hidden]").name = `${zone.dataset.zone}[]`
        item.querySelector("[data-move=up]").disabled = index === 0
        item.querySelector("[data-move=down]").disabled = index === items.length - 1
        item.querySelector("[data-toggle]")?.setAttribute("aria-label",
          `${zone.dataset.zone === "shown" ? "Hide" : "Show"} ${item.dataset.label}`)
      })
    })
  }

  #step(button, offset) {
    const item = button.closest("[data-column]")
    const items = this.#items(item.parentElement)
    const neighbour = items[items.indexOf(item) + offset]
    if (!neighbour) return

    offset < 0 ? neighbour.before(item) : neighbour.after(item)
    this.sync()
    // At either end its own button is disabled, so focus goes to the other.
    const other = item.querySelector(`[data-move=${offset < 0 ? "down" : "up"}]`)
    ;(button.disabled ? other : button).focus()
    this.#announce(item)
  }

  #accepts(zone, item) {
    return zone.dataset.zone === "shown" || item.dataset.required !== "true"
  }

  #items(zone) {
    return [...zone.querySelectorAll(":scope > [data-column]")]
  }

  #placeholder(zone) {
    return zone.querySelector(":scope > [data-placeholder]")
  }

  #itemBelow(zone, y) {
    return this.#items(zone).filter(item => item !== this.dragged).find(item => {
      const box = item.getBoundingClientRect()
      return y < box.top + box.height / 2
    })
  }

  // Moves happen without a page change, so screen readers are told.
  #announce(item) {
    const items = this.#items(item.parentElement)
    this.statusTarget.textContent =
      `${item.dataset.label} ${item.parentElement.dataset.zone}, ${items.indexOf(item) + 1} of ${items.length}.`
  }
}
