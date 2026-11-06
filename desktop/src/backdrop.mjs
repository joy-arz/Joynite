export class Backdrop {
  constructor(layers, createImage = () => new Image()) {
    this.layers = layers;
    this.createImage = createImage;
    this.revision = 0;
    this.index = 0;
    this.requested = null;
  }

  async show(asset, fillAsset = "") {
    const key = JSON.stringify([asset, fillAsset]);
    if (key === this.requested) return;
    this.requested = key;
    const revision = ++this.revision;
    if (!asset) {
      for (const { image, fill } of this.layers) {
        image.classList.remove("shown");
        fill.classList.remove("shown");
      }
      return;
    }
    // Decode away from the displayed layers. Rapid selection cannot replace
    // the pixels of a layer while its previous request is still resolving.
    const decoded = this.createImage();
    decoded.src = asset;
    try {
      await decoded.decode();
    } catch {
      if (revision === this.revision) this.requested = null;
      return;
    }
    if (revision !== this.revision) return;
    const nextIndex = 1 - this.index;
    const next = this.layers[nextIndex], old = this.layers[this.index];
    next.image.src = asset;
    next.fill.hidden = !fillAsset;
    if (fillAsset) next.fill.src = fillAsset;
    else next.fill.removeAttribute("src");
    next.image.classList.add("shown");
    next.fill.classList.add("shown");
    old.image.classList.remove("shown");
    old.fill.classList.remove("shown");
    this.index = nextIndex;
  }
}
