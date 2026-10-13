import { Controller } from "@hotwired/stimulus"

/*
  Keeps detail rows hidden until asked for, so long lists stay scannable,
  while screen readers still know whether each one is open.
*/
export default class extends Controller {
  static targets = [ "button", "panel" ]

  toggle() {
    const expanded = this.buttonTarget.getAttribute("aria-expanded") === "true"
    this.buttonTarget.setAttribute("aria-expanded", String(!expanded))
    this.panelTarget.hidden = expanded
  }
}
