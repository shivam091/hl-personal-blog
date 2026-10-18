import { Controller } from "@hotwired/stimulus"

/*
  The token is fetched as the form is sent rather than on page load, since
  tokens expire two minutes after they're issued. A form without one still
  goes, so the server can say what's wrong rather than the button doing
  nothing.
*/
export default class extends Controller {
  static targets = [ "token" ]
  static values = { siteKey: String, action: String }

  submit(event) {
    if (this.tokenReady) {
      this.tokenReady = false
      return
    }
    event.preventDefault()

    const send = (token = "") => {
      this.tokenTarget.value = token
      this.tokenReady = true
      this.element.requestSubmit()
    }
    if (!window.grecaptcha) return send()

    window.grecaptcha.ready(() => {
      window.grecaptcha.execute(this.siteKeyValue, { action: this.actionValue }).then(send, () => send())
    })
  }
}
