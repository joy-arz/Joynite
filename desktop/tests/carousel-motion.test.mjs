import test from "node:test";
import assert from "node:assert/strict";
import { CarouselMotion, cardGeometry } from "../src/carousel-motion.mjs";
import { slots } from "../src/model.mjs";

test("spring is independent of refresh rate and settles after a dropped frame", () => {
  const run = (hz, seconds = 1) => {
    const motion = new CarouselMotion();
    for (let i = 0; i <= hz * seconds; i++) motion.advance(1, i * 1000 / hz);
    return motion;
  };
  assert(Math.abs(run(60, 0.1).position - run(120, 0.1).position) < 1e-12);
  assert.equal(run(60).position, 1);
  assert.equal(run(120).position, 1);
  const motion = new CarouselMotion();
  motion.advance(1, 0);
  motion.advance(1, 100);
  assert(motion.position > 0 && motion.position < 1);
  motion.advance(1, 5000);
  assert.equal(motion.position, 1);
  assert.equal(motion.velocity, 0);
});

test("rapid reversal retains position and velocity without queuing old targets", () => {
  const motion = new CarouselMotion();
  motion.advance(4, 0);
  motion.advance(4, 80);
  const { position, velocity } = motion;
  motion.advance(-3, 80);
  assert.equal(motion.position, position);
  assert.equal(motion.velocity, velocity);
  for (let time = 96; time <= 2000; time += 16) motion.advance(-3, time);
  assert.equal(motion.position, -3);
});

test("reduced motion immediately settles even when enabled mid-flight", () => {
  const motion = new CarouselMotion();
  motion.advance(2, 0);
  motion.advance(2, 50);
  assert.equal(motion.advance(2, 60, true), false);
  assert.equal(motion.position, 2);
  assert.equal(motion.velocity, 0);
});

test("Mac geometry interpolates continuously and keeps nine slots around the visible position", () => {
  assert(cardGeometry(0, 300).transform.includes('-10px'));
  assert(cardGeometry(1, 300).transform.includes('240px'));
  assert.equal(cardGeometry(2, 300).opacity, 0.5);
  assert.equal(cardGeometry(3, 300).opacity, 0);
  const left = cardGeometry(0.999999, 300), right = cardGeometry(1.000001, 300);
  assert(Math.abs(left.opacity - right.opacity) < 0.00001);
  const games = [{ id: 'a' }, { id: 'b' }];
  for (const position of [-500, -1, 0, 1, 500]) {
    const cards = slots(position, games);
    assert.equal(cards.length, 9);
    assert.equal(new Set(cards.map(c => c.key)).size, 9);
    assert.equal(cards[4].key, position);
    assert(cards.every(c => c.game));
  }
});
