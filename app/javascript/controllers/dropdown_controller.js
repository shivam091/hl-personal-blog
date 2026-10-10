import { Controller } from "@hotwired/stimulus"

// Menus keep the nav bar short as categories grow.
export default class extends Controller {
  static targets = [ "button", "menu" ]
  static values = { side: Boolean }

  connect() {
    this.closeOnOutsideClick = (event) => { if (!this.element.contains(event.target)) this.close() }
    document.addEventListener("click", this.closeOnOutsideClick)
  }

  disconnect() {
    document.removeEventListener("click", this.closeOnOutsideClick)
  }

  toggle() {
    this.menuTarget.hidden ? this.open() : this.close()
  }

  open() {
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.menuTarget.hidden = false
    this.place()
  }

  /*
    The same button sits at either end of a toolbar depending on the
    screen, so the menu opens toward whichever side has room rather than
    off the edge.
  */
  place() {
    this.sideValue ? this.placeBeside() : this.placeBelow()
  }

  placeBelow() {
    const menu = this.menuTarget
    const margin = 8
    Object.assign(menu.style, { left: "0px", right: "auto", top: "", bottom: "", marginTop: "", marginBottom: "" })

    const anchor = this.element.getBoundingClientRect()
    const { width, height } = menu.getBoundingClientRect()
    const viewportWidth = document.documentElement.clientWidth
    let left = anchor.left + width > viewportWidth - margin ? anchor.width - width : 0
    left = Math.min(Math.max(left, margin - anchor.left), viewportWidth - margin - width - anchor.left)
    menu.style.left = `${left}px`

    const gap = parseFloat(getComputedStyle(menu).marginTop) || 0
    const below = window.innerHeight - anchor.bottom - gap - margin
    const above = anchor.top - gap - margin
    if (height > below && above > below) {
      Object.assign(menu.style, { top: "auto", bottom: "100%", marginTop: "0px", marginBottom: `${gap}px` })
    }
  }

  /*
    A submenu clears its parent menu's padding and border so the two read
    as separate panels, and lines its first link up with its button.
  */
  placeBeside() {
    const menu = this.menuTarget
    const margin = 8
    const offset = 10
    const inset = -7
    Object.assign(menu.style, { left: `calc(100% + ${offset}px)`, right: "auto", top: `${inset}px` })

    const anchor = this.element.getBoundingClientRect()
    const { width, height } = menu.getBoundingClientRect()
    if (anchor.right + offset + width > document.documentElement.clientWidth - margin) {
      Object.assign(menu.style, { left: "auto", right: `calc(100% + ${offset}px)` })
    }

    const overflow = anchor.top + inset + height - (window.innerHeight - margin)
    if (overflow > 0) menu.style.top = `${inset - Math.min(overflow, anchor.top + inset - margin)}px`
  }

  close() {
    this.buttonTarget.setAttribute("aria-expanded", "false")
    this.menuTarget.hidden = true
  }

  /*
    Focus goes back to the button so keyboard users don't lose their place,
    and Escape in a submenu leaves its parent open so it backs out one level.
  */
  closeWithKeyboard(event) {
    if (event.key !== "Escape" || this.menuTarget.hidden) return

    event.stopPropagation()
    this.close()
    this.buttonTarget.focus()
  }
}
