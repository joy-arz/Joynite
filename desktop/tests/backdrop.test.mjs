import test from "node:test";
import assert from "node:assert/strict";
import { JSDOM } from "jsdom";
import { Backdrop } from "../src/backdrop.mjs";

test("stale decodes cannot overwrite the current background; failed images can retry", async () => {
  const document = new JSDOM('<img><img><img><img>').window.document;
  const imgs = [...document.querySelectorAll('img')];
  const layers = [{ image: imgs[0], fill: imgs[1] }, { image: imgs[2], fill: imgs[3] }];
  const requests = [];
  const backdrop = new Backdrop(layers, () => {
    const image = { decode: () => new Promise((resolve, reject) => requests.push({ resolve, reject })) };
    return image;
  });
  const first = backdrop.show('old.png');
  const second = backdrop.show('new.png', 'fill.png');
  requests[1].resolve(); await second;
  requests[0].resolve(); await first;
  assert.equal(imgs[2].getAttribute('src'), 'new.png');
  assert(imgs[2].classList.contains('shown'));
  const failed = backdrop.show('retry.png');
  requests[2].reject(Error('decode')); await failed;
  const retried = backdrop.show('retry.png');
  assert.equal(requests.length, 4);
  requests[3].resolve(); await retried;
  assert.equal(imgs[0].getAttribute('src'), 'retry.png');
  const pending = backdrop.show('stale.png');
  await backdrop.show('');
  requests[4].resolve(); await pending;
  assert(imgs.every(image => !image.classList.contains('shown')));
});
