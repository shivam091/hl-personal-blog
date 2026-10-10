import { Controller } from "@hotwired/stimulus"

/*
  A phone has no room for a bar of menus, so the whole navigation opens as
  one panel under the header. The page behind is held still while it's open,
  so a swipe scrolls the menu rather than the list underneath it.
*/
export default class extends Controller {
  static targets = [ "button", "panel", "section" ]

  connect() {
    // Widening past the phone layout swaps in the desktop bar, which a
    // panel left open would sit on top of.
    this.wide = window.matchMedia("(min-width: 48rem)")
    this.closeWhenWide = (event) => { if (event.matches) this.close() }
    this.wide.addEventListener("change", this.closeWhenWide)
  }

  disconnect() {
    this.wide.removeEventListener("change", this.closeWhenWide)
    this.unlockPage()
  }

  toggle() {
    this.panelTarget.hidden ? this.open() : this.close()
  }

  open() {
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.panelTarget.hidden = false
    document.documentElement.style.overflow = "hidden"
  }

  close() {
    if (this.panelTarget.hidden) return

    this.buttonTarget.setAttribute("aria-expanded", "false")
    this.panelTarget.hidden = true
    this.unlockPage()
  }

  // Focus goes back to the button so keyboard users don't lose their place.
  closeWithKeyboard(event) {
    if (event.key !== "Escape" || this.panelTarget.hidden) return

    this.close()
    this.buttonTarget.focus()
  }

  /*
    Sections sharing a name already do this where browsers support it;
    this covers those that don't.
  */
  closeOtherSections(event) {
    if (!event.target.open) return

    this.sectionTargets.forEach((section) => { if (section !== event.target) section.open = false })
  }

  unlockPage() {
    document.documentElement.style.overflow = ""
  }
}
