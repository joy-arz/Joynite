// SwiftUI's interactiveSpring(response: 0.42, dampingFraction: 0.92).
// Solve the damped oscillator analytically so 60/120 Hz and dropped frames agree.
export class CarouselMotion {
  position = 0;
  velocity = 0;
  target = 0;
  time = null;

  snap(position) {
    this.position = this.target = position;
    this.velocity = 0;
    this.time = null;
  }

  advance(target, time, reduced = false) {
    if (reduced) {
      this.snap(target);
      return false;
    }
    const dt = this.time === null ? 0 : Math.max(0, (time - this.time) / 1000);
    this.time = time;
    this.target = target;
    const omega = 2 * Math.PI / 0.42;
    const decay = omega * 0.92;
    const frequency = omega * Math.sqrt(1 - 0.92 ** 2);
    const displacement = this.position - target;
    const a = displacement;
    const b = (this.velocity + decay * displacement) / frequency;
    const cos = Math.cos(frequency * dt), sin = Math.sin(frequency * dt);
    const envelope = Math.exp(-decay * dt);
    this.position = target + envelope * (a * cos + b * sin);
    this.velocity = envelope * (
      -decay * (a * cos + b * sin) + frequency * (-a * sin + b * cos)
    );
    if (Math.abs(this.position - target) < 0.0001 && Math.abs(this.velocity) < 0.001) {
      this.snap(target);
      return false;
    }
    return true;
  }
}

export function cardGeometry(offset, width) {
  const distance = Math.abs(offset);
  const stops = [
    [0, 1, -10, 1], [0.8, 0.78, 10, 0.83],
    [1.37, 0.59, 20, 0.50], [1.85, 0.45, 30, 0],
    [2.3, 0.45, 40, 0],
  ];
  const index = Math.min(3, Math.floor(distance));
  const fraction = Math.min(1, distance - index);
  const values = stops[index].map((value, i) => value + (stops[index + 1][i] - value) * fraction);
  return {
    transform: `translate3d(calc(-50% + ${Math.sign(offset) * values[0] * width}px),calc(-50% + ${values[2]}px),0) scale(${values[1]})`,
    opacity: values[3],
  };
}
