'use strict';
class Interaction {
  constructor() { this.gesture = null; this.shape = null; this.ignored = null; }
  begin(mode, point, bounds, yaw, now = Date.now()) {
    if (!['move', 'rotate', 'pet', 'control'].includes(mode)) throw new Error('Gesto desconocido.');
    this.gesture = { mode, point: { ...point }, bounds: { ...bounds }, yaw, moved: false, petted: false, lastPoint: { ...point }, lastActivity: now };
  }
  step(point, now = Date.now()) {
    const g = this.gesture;
    if (!g) return null;
    if (point.x !== g.lastPoint.x || point.y !== g.lastPoint.y) { g.lastActivity = now; g.lastPoint = { ...point }; }
    if (now - g.lastActivity > 15000) { this.end(true); return { cancelled: true }; }
    if (g.mode === 'control') return {};
    const dx = point.x - g.point.x, dy = point.y - g.point.y;
    g.moved ||= Math.hypot(dx, dy) > 4;
    if (!g.moved) return {};
    if (g.mode === 'move') return { bounds: { ...g.bounds, x: g.bounds.x + dx, y: g.bounds.y + dy } };
    if (g.mode === 'rotate') return { yaw: g.yaw + dx * 0.012 };
    if (!g.petted) { g.petted = true; return { pet: true }; }
    return {};
  }
  end(cancelled = false) {
    const g = this.gesture; this.gesture = null;
    return g ? { mode: g.mode, moved: g.moved, click: g.mode !== 'control' && !cancelled && !g.moved, cancelled } : null;
  }
  shouldIgnore(hit) { return !this.gesture && !hit; }
  updateIgnored(value, apply) {
    if (this.ignored !== value) { apply(value); this.ignored = value; }
  }
}
module.exports = { Interaction };
