import { Controller } from "@hotwired/stimulus"

/*
  A native <dialog> already traps focus and draws a backdrop, so only what
  it lacks lives here. Only an explicit button closes it, so a stray Escape
  or backdrop tap can't throw away what's been typed.
*/
export default class extends Controller {
  static targets = [ "dialog" ]
  static values = { open: Boolean }

  connect() {
    if (this.openValue) this.open()
  }

  open() {
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  /*
    Closing in place keeps the page behind as it was, and emptying the frame
    lets the same link load the dialog again. A dialog opened as a page of
    its own has nothing behind it, so its link is followed instead.
  */
  dismiss(event) {
    if (!this.#loadedIntoFrame) return

    event.preventDefault()
    this.#discard()
  }

  // A dialog left in the snapshot Turbo keeps for Back would reopen there.
  beforeCache() {
    this.#loadedIntoFrame ? this.#discard() : this.close()
  }

  get #loadedIntoFrame() {
    return this.element.closest("turbo-frame")?.hasAttribute("src")
  }

  #discard() {
    this.close()
    this.element.closest("turbo-frame").removeAttribute("src")
    this.element.remove()
  }

  /*
    Both keydown and cancel must be stopped, since either alone still lets
    Escape close the dialog. Some browsers still close it on a repeated
    cancel such as Android's back gesture, which pages can't override.
  */
  preventDismiss(event) {
    event.preventDefault()
  }
}
