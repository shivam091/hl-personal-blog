import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  change() {
    Turbo.visit(this.element.value)
  }
}
