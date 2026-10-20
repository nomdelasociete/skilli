import { tiltFromOrientation, TILT_YAW, TILT_PITCH } from '../brand-glass/tilt.js';

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const flat = tiltFromOrientation(50, 0);
assert(Math.abs(flat.x) < 1e-9 && Math.abs(flat.y) < 1e-9, 'rest pose is centered');

const yaw = tiltFromOrientation(50, 90);
assert(Math.abs(yaw.y - TILT_YAW) < 1e-9, 'gamma 90 maps to +10 degrees');
assert(Math.abs(tiltFromOrientation(50, -90).y + TILT_YAW) < 1e-9, 'gamma -90 maps to -10 degrees');

const pitch = tiltFromOrientation(95, 0);
assert(Math.abs(pitch.x - TILT_PITCH) < 1e-9, 'beta 95 maps to +6 degrees');
assert(Math.abs(tiltFromOrientation(5, 0).x + TILT_PITCH) < 1e-9, 'beta 5 maps to -6 degrees');

const clamped = tiltFromOrientation(200, 180);
assert(clamped.x === TILT_PITCH && clamped.y === TILT_YAW, 'out of range stays at the desktop cap');

assert(Math.abs(TILT_YAW - 0.175) < 1e-9 && Math.abs(TILT_PITCH - 0.1) < 1e-9, 'same radians as the pointer');
console.log('tilt ok');
