import { Controller } from "@hotwired/stimulus"

/*
  The picture is always on white, whatever the page shows, so it pastes
  into a document cleanly. The title and period are drawn on it because
  a chart cut out of its card says neither.
*/
const PADDING = 24
const SCALE = 2
// What a shape's class decides, which the picture has no stylesheet to
// resolve; without these a bar or a country is painted black.
const PAINT = [ "fill", "stroke", "stroke-width", "stroke-dasharray", "stroke-linecap", "stroke-linejoin", "stroke-opacity", "fill-opacity", "opacity" ]

export default class extends Controller {
  // The readout follows the pointer and the arrow keys, which the button
  // sits inside of.
  stop(event) {
    event.stopPropagation()
  }

  async download(event) {
    event.stopPropagation()
    const button = event.currentTarget
    button.disabled = true
    document.documentElement.setAttribute("data-exporting", "")
    const restore = await this.#inlineIcons(this.#subject)
    const unpin = this.#pinPaint(this.#subject)

    try {
      const { toCanvas } = await import("html-to-image")
      const chart = await toCanvas(this.#subject, {
        pixelRatio: SCALE,
        backgroundColor: "#ffffff",
        filter: node => !(node instanceof Element && (("exportSkip" in (node.dataset || {})) || node.hasAttribute("hidden")))
      })
      this.#save(this.#framed(chart))
    } finally {
      unpin()
      restore()
      document.documentElement.removeAttribute("data-exporting")
      button.disabled = false
    }
  }

  /*
    An icon is a reference to a shape in a sprite file, which a picture
    made of the page can't fetch, so each draws as blank. Its shapes are
    placed beside the reference for the capture, which is set aside.
  */
  async #inlineIcons(root) {
    const uses = [ ...root.querySelectorAll("svg use") ].filter(use => (use.getAttribute("href") || "").includes("#"))
    if (!uses.length) return () => {}

    const sprites = new Map()
    const added = []
    for (const use of uses) {
      const [ file, id ] = use.getAttribute("href").split("#")
      if (!sprites.has(file)) {
        const text = await fetch(file).then(response => response.text()).catch(() => "")
        sprites.set(file, new DOMParser().parseFromString(text, "image/svg+xml"))
      }
      const symbol = sprites.get(file).getElementById(id)
      if (!symbol) continue

      const group = document.createElementNS("http://www.w3.org/2000/svg", "g")
      group.dataset.exportIcon = ""
      symbol.childNodes.forEach(node => group.append(document.importNode(node, true)))
      use.after(group)
      use.dataset.exportSkip = ""
      added.push([ use, group ])
    }
    return () => added.forEach(([ use, group ]) => {
      group.remove()
      delete use.dataset.exportSkip
    })
  }

  /*
    The library copies computed styles onto HTML but not onto the shapes
    inside an SVG, so each takes its resolved paint as an inline style for
    the capture. A paint that points at a gradient is left to its own
    attribute, since the resolved address is the page's and means nothing in
    the picture.
  */
  #pinPaint(root) {
    const pinned = []
    root.querySelectorAll("svg *").forEach(shape => {
      const computed = getComputedStyle(shape)
      PAINT.forEach(name => {
        const value = computed.getPropertyValue(name)
        if (!value || value.startsWith("url(") || shape.style.getPropertyValue(name)) return

        shape.style.setProperty(name, value)
        pinned.push([ shape, name ])
      })
    })
    return () => pinned.forEach(([ shape, name ]) => shape.style.removeProperty(name))
  }

  // The figure carries the legend beside the plot; a chart without one is
  // taken as it stands.
  get #subject() {
    return this.element.closest("figure") || this.element
  }

  get #title() {
    return this.element.closest("section")?.querySelector("h2")?.textContent.trim() ||
      this.element.getAttribute("aria-label")?.split(". ")[0] || "Chart"
  }

  get #footer() {
    const period = document.querySelector("[data-export-period]")?.textContent.trim()
    return [ period, location.host ].filter(Boolean).join(" · ")
  }

  #framed(chart) {
    const family = getComputedStyle(document.body).fontFamily
    const head = 28 * SCALE
    const foot = 24 * SCALE
    const pad = PADDING * SCALE
    const canvas = document.createElement("canvas")
    canvas.width = chart.width + pad * 2
    canvas.height = chart.height + pad * 2 + head + foot

    const context = canvas.getContext("2d")
    context.fillStyle = "#ffffff"
    context.fillRect(0, 0, canvas.width, canvas.height)
    context.textBaseline = "top"
    context.fillStyle = "#334155"
    context.font = `600 ${15 * SCALE}px ${family}`
    context.fillText(this.#title, pad, pad)
    context.drawImage(chart, pad, pad + head)
    context.fillStyle = "#64748b"
    context.font = `${11 * SCALE}px ${family}`
    context.fillText(this.#footer, pad, pad + head + chart.height + 12 * SCALE)
    return canvas
  }

  #save(canvas) {
    canvas.toBlob(blob => {
      const link = document.createElement("a")
      const name = this.#title.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")
      link.download = `${name || "chart"}-${new Date().toISOString().slice(0, 10)}.png`
      link.href = URL.createObjectURL(blob)
      link.click()
      URL.revokeObjectURL(link.href)
    })
  }
}
