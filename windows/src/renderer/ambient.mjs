// Presentation only. Never persist the changing offset or allocate another timer.
export function ambientRotationAllowed(state) {
  return state.settings.ambientRotation !== false && !state.menuOpen && !state.panelOpen && !state.notice && !(state.focus && !state.focus.paused) && !state.smokeTest;
}
export class AmbientRotation {
  static amplitude = 25 * Math.PI / 180;
  static period = 480;
  angle = 0; phase = 0; lastTime = null; holdUntil = 0;
  hold(now) { this.holdUntil = now + 20; }
  reset(now) { this.phase = 0; this.angle = 0; this.lastTime = now; this.hold(now); }
  tick(now, allowed) {
    if (!Number.isFinite(now)) return this.angle;
    const delta = Math.min(.1, Math.max(0, now - (this.lastTime ?? now)));
    this.lastTime = now;
    if (!allowed || now < this.holdUntil) return this.angle;
    this.phase = (this.phase + delta * 2 * Math.PI / AmbientRotation.period) % (2 * Math.PI);
    return this.angle = AmbientRotation.amplitude * Math.sin(this.phase);
  }
}
