export const PET_SIZE = { width: 620, height: 520 };
export const STAGE = { x: 94, y: 184, width: 432, height: 304 };
export const ARC_SIZE = { width: 548, height: 190 };
export const DEFAULT_BODY = { left: 204, top: 234, right: 414, bottom: 464 };
const clamp = (v, lo, hi) => Math.max(lo, Math.min(v, hi));
export function attachments(body, viewport = PET_SIZE) {
  const center = (body.left + body.right) / 2;
  return {
    arc: { x: clamp(center - ARC_SIZE.width / 2, 2, viewport.width - ARC_SIZE.width - 2), y: Math.max(2, body.top - 188), ...ARC_SIZE },
    timer: { x: center, y: clamp(body.bottom + 4, 0, viewport.height - 30) }
  };
}
export function visibleBounds(body, menuOpen, timerOpen, viewport = PET_SIZE) {
  const result = { ...body }, a = attachments(body, viewport);
  if (menuOpen) {
    result.left = Math.min(result.left, a.arc.x);
    result.right = Math.max(result.right, a.arc.x + a.arc.width);
    result.top = Math.min(result.top, a.arc.y);
    result.bottom=Math.max(result.bottom,a.arc.y+a.arc.height);
  }
  if (timerOpen) {
    result.left = Math.min(result.left, a.timer.x - 48);
    result.right = Math.max(result.right, a.timer.x + 48);
    result.bottom = Math.max(result.bottom, a.timer.y + 26);
  }
  return result;
}
export function fitVisibleWindow(bounds, visible, workArea) {
  const sx = bounds.width / PET_SIZE.width, sy = bounds.height / PET_SIZE.height;
  const minX = workArea.x + 8 - visible.left * sx;
  const maxX = workArea.x + workArea.width - 8 - visible.right * sx;
  const minY = workArea.y + 8 - visible.top * sy;
  const maxY = workArea.y + workArea.height - 8 - visible.bottom * sy;
  return { ...bounds, x: Math.round(clamp(bounds.x, minX, Math.max(minX, maxX))), y: Math.round(clamp(bounds.y, minY, Math.max(minY, maxY))) };
}
export function migratePosition(saved, workArea, demo = false) {
  if (saved && Number.isFinite(saved.x) && Number.isFinite(saved.y)) {
    const width = Number.isFinite(saved.width) ? saved.width : 252;
    const height = Number.isFinite(saved.height) ? saved.height : 288;
    return { x: saved.x + width / 2 - PET_SIZE.width / 2, y: saved.y + height - PET_SIZE.height, ...PET_SIZE };
  }
  return { x: workArea.x + (demo ? 150 : workArea.width - 530), y: workArea.y + workArea.height - 550, ...PET_SIZE };
}
export function restorePosition(saved, workArea, scale = 1, demo = false) {
  const fresh=migratePosition(null,workArea,demo);
  return {x:Number.isFinite(saved?.x)?saved.x:fresh.x,y:Number.isFinite(saved?.y)?saved.y:fresh.y,
    width:Math.round(PET_SIZE.width*scale),height:Math.round(PET_SIZE.height*scale)};
}
export function maskHit(mask, x, y, padding = 1) {
  if (!mask || x < 0 || y < 0 || x >= mask.width || y >= mask.height) return false;
  const px = Math.floor(x), py = Math.floor(y);
  for (let j = Math.max(0, py - padding); j <= Math.min(mask.height - 1, py + padding); j++) {
    for (let i = Math.max(0, px - padding); i <= Math.min(mask.width - 1, px + padding); i++) if (mask.data[j * mask.width + i]) return true;
  }
  return false;
}
export function shapeHit(shape, point, contentBounds) {
  if (!shape) return false;
  const x = (point.x - contentBounds.x) * shape.viewport.width / contentBounds.width;
  const y = (point.y - contentBounds.y) * shape.viewport.height / contentBounds.height;
  if (shape.controls.some(r => x >= r.left && x < r.right && y >= r.top && y < r.bottom)) return true;
  const s = shape.stage;
  return maskHit(shape.mask, (x - s.x) * shape.mask.width / s.width, (y - s.y) * shape.mask.height / s.height);
}
