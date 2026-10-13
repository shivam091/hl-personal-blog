import { Controller } from "@hotwired/stimulus"

/*
  Ticking rows gathers them for one action, so handling a handful of rows
  doesn't take a click (or a confirm) per row.
*/
export default class extends Controller {
  static targets = [ "all", "item", "count", "submit", "form" ]
  // Only destructive actions confirm, so confirm is left blank for the rest.
  static values = { one: String, many: String, confirm: String }

  // Browsers can restore ticked boxes on Back, so start from what's ticked.
  connect() {
    this.update()
  }

  toggleAll() {
    this.itemTargets.forEach(item => item.checked = this.allTarget.checked)
    this.update()
  }

  update() {
    const total = this.itemTargets.length
    const selected = this.itemTargets.filter(item => item.checked).length
    const items = `${selected} ${selected === 1 ? this.oneValue : this.manyValue}`

    this.allTarget.checked = total > 0 && selected === total
    this.allTarget.indeterminate = selected > 0 && selected < total
    this.countTarget.textContent = selected ? `${items} selected` : `No ${this.manyValue} selected`
    this.submitTargets.forEach(submit => submit.disabled = selected === 0)
    if (this.confirmValue) this.formTarget.dataset.turboConfirm = this.confirmValue.replace("{items}", items)
  }
}
