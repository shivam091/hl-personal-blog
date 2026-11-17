# encoding: UTF-8

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "html-to-image", to: "html-to-image.js"

# Not preloaded: controllers are lazy-loaded when their markup appears, and
# preloading would download them all up front anyway.
pin_all_from "app/javascript/controllers", under: "controllers", preload: false
