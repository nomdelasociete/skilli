// Same range as the desktop pointer: yaw ±10° (0.175 rad), pitch ±6° (0.1 rad).
export const TILT_YAW = 0.175;
export const TILT_PITCH = 0.1;

export function tiltFromOrientation(beta, gamma) {
  const y = Math.max(-TILT_YAW, Math.min(TILT_YAW, (Number(gamma) || 0) / 90 * TILT_YAW));
  const x = Math.max(-TILT_PITCH, Math.min(TILT_PITCH, ((Number(beta) || 0) - 50) / 45 * TILT_PITCH));
  return { x, y };
}
