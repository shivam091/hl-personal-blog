import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

/*
  Each option is a page of its own, so picking one goes there as a tab's
  link would.
*/
export default class extends Controller {
  change() {
    Turbo.visit(this.element.value)
  }
}
