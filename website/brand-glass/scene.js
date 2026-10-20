
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { RGBELoader } from 'three/addons/loaders/RGBELoader.js';
import { tiltFromOrientation, TILT_YAW, TILT_PITCH } from './tilt.js';

const params = new URLSearchParams(location.search);
const mode = params.get('mode') || 'front';
const isScroll = mode === 'scroll';
let detail = null;
let followup = null;
let scrollProgress = 0;
let renderer;
let failed = false;
try { renderer = new THREE.WebGLRenderer({ antialias: true }); }
catch (error) { fail(); throw error; }
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.toneMapping = THREE.NoToneMapping;          // brand colours as authored
document.body.prepend(renderer.domElement);

const scene = new THREE.Scene();
// Orthographic, like the Blender camera: the front view is the approved S,
// and tilting reveals the folds without perspective squashing the diagonal.
const FRAME = isScroll ? 5.8 : 270 / 0.72 * 0.01;                     // viewBox fills 72 % of the short side
const camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 50);
camera.position.set(-0.0775, -0.0025, 12);           // viewBox centre vs logo centre (m)

// The website's halo (website/halo.js, menthe), as a mesh behind the logo so
// the glass transmission really refracts it.
const halo = new THREE.Mesh(
  new THREE.PlaneGeometry(1, 1),
  new THREE.ShaderMaterial({
    uniforms: { t: { value: 3 } },
    depthWrite: false,
    vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.); }',
    fragmentShader: `varying vec2 vUv; uniform float t;
      float blob(vec2 p, vec2 c, float r){ return exp(-dot(p - c, p - c) * r); }
      void main(){
        vec2 p = vUv; float time = t * .38;
        float a = blob(p, vec2(.64 + .22 * sin(time), .70 + .18 * cos(time * .8)), 5.3 + .7 * sin(time * .65));
        float b = blob(p, vec2(.16 + .13 * cos(time * .75), .18 + .18 * sin(time * .9)), 7.);
        vec3 col = mix(vec3(.015, .09, .13), vec3(.06, .58, .55), a);
        col += vec3(.12, .25, .31) * b;
        float h = blob(p, vec2(.75 + .18 * sin(time * .85 + .7), .86 + .12 * cos(time * .7)), 16.);
        col += vec3(.25, .34, .22) * h;
        gl_FragColor = vec4(pow(col, vec3(2.2)), 1.);  // sRGB-authored → linear
        #include <colorspace_fragment>
 gl_FragColor.rgb += (fract(sin(dot(gl_FragCoord.xy,vec2(12.9898,78.233)))*43758.5453)-.5)*.008;
      }`,
  }),
);
halo.position.set(camera.position.x, camera.position.y, -3);
scene.add(halo);

// Detail behind the logo (the site's headline), to see what the glass does.
function makeDetail() {
  const c = document.createElement('canvas');
  c.width = 2048; c.height = 1024;
  const g = c.getContext('2d');
  g.fillStyle = '#dbf2ec';
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  g.font = '400 140px "Geist Pixel line", monospace';
  g.letterSpacing = '-5.6px';
  g.fillText('Being skilled', 1024, 430);
  g.fillText('is your first nature.', 1024, 586.8);
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  const m = new THREE.Mesh(new THREE.PlaneGeometry(4.2, 2.1),
    new THREE.MeshBasicMaterial({ map: tex, alphaTest: 0.5 }));   // opaque cut-out: transmission only sees opaque objects
  m.position.set(camera.position.x, camera.position.y + 0.02, -2.9);
  m.renderOrder = 1;
  return m;
}
function makeFollowup() {
  const canvas = document.createElement('canvas');
  canvas.width = 2048; canvas.height = 256;
  const ctx = canvas.getContext('2d');
  ctx.font = '300 96px "Trueno"';
  ctx.letterSpacing = '-2.4px';
  ctx.fillStyle = '#c1dbd0';
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  ctx.fillText('Your Mac must keep up.', 1024, 128);
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  const mesh = new THREE.Mesh(new THREE.PlaneGeometry(1, .125),
    new THREE.MeshBasicMaterial({map:texture, alphaTest:.5}));
  mesh.position.set(camera.position.x, 0, -2.9);
  mesh.renderOrder = 1;
  return mesh;
}
if (isScroll || params.get('text') === '1') {
  Promise.all([document.fonts.load('140px "Geist Pixel line"'), document.fonts.load('300 96px "Trueno"')]).then(() => {
    detail = makeDetail();
    scene.add(detail);
    if (isScroll && params.get('domTitle') === '1') { followup = makeFollowup(); scene.add(followup); }
    applyScroll();
    sync();
  }).catch(fail);
}

const logo = new THREE.Group();
scene.add(logo);
if (mode === 'social') { logo.position.x = 2.05; logo.scale.setScalar(1.2); }
function smooth(start, end, value) {
  const t = THREE.MathUtils.clamp((value - start) / (end - start), 0, 1);
  return t * t * (3 - 2 * t);
}
function applyScroll() {
  if (!isScroll) return;
  const cross = smooth(0.04, 0.70, scrollProgress);
  const leave = smooth(0.74, 1, scrollProgress);
  logo.scale.setScalar(0.78);
  const lift = Math.max(1, innerHeight / innerWidth);
  logo.position.y = (1.18 + leave * 0.85) * lift;
  // Tilt only as the mark leaves; the text crosses a steady, readable S.
  logo.rotation.y = reduce.matches ? 0 : pointerRotation.y * (1 - leave) + leave * 0.55;
  logo.rotation.x = reduce.matches ? 0 : pointerRotation.x * (1 - leave);
  logo.rotation.z = reduce.matches ? 0 : leave * -0.13;
  if (detail) {
    detail.visible = params.get('domTitle') !== '1' || scrollProgress >= .24;
    const fontSize = innerWidth <= 700 ? Math.max(27, Math.min(44, innerWidth * .066)) : Math.max(38, Math.min(69, innerWidth * .046));
    const worldPerPixel = (camera.top - camera.bottom) / innerHeight;
    const width = 2048 / 140 * fontSize * worldPerPixel;
    const firstLineCenter = innerHeight * (innerWidth <= 700 ? .53 : .54) + fontSize * .56;
    detail.position.y = camera.top - firstLineCenter * worldPerPixel - 82 / 2048 * width + cross * 2.7 + leave * .35;
    detail.scale.setScalar(width / 4.2);
    if (followup) {
      followup.visible = detail.visible;
      const size = Math.max(17, Math.min(23, innerWidth * .018));
      const center = innerHeight * (innerWidth <= 700 ? .53 : .54) + fontSize * 2.24 + 24 + size * .7;
      followup.scale.setScalar(2048 / 96 * size * worldPerPixel);
      followup.position.y = camera.top - center * worldPerPixel + cross * 2.7 + leave * .35;
    }
  }
}
addEventListener('message', event => {
  if (event.origin !== location.origin || event.source !== parent) return;
  if (event.data?.type === 'logo-scroll') {
    scrollProgress = THREE.MathUtils.clamp(Number(event.data.progress) || 0, 0, 1);
    applyScroll();
    if (reduce.matches || params.get('pause') === '1') sync();
    return;
  }
  if (event.data?.type !== 'logo-tilt' || reduce.matches) return;
  if ('beta' in event.data || 'gamma' in event.data) onOrient(event.data);
});

if(mode !== 'png') new RGBELoader().load('../../assets/brand/3d/studio-env.hdr', (tex) => {
  tex.mapping = THREE.EquirectangularReflectionMapping;
  scene.environment = tex;
  sync();
}, undefined, fail);
// The site's glass recipe, inside three.js's transmission: what the ribbon
// refracts is the halo at brightness(1.65) saturate(.72) (style.css,
// .halo-refraction), under a milky cyan face (the SVG "face" layer). The
// ribbon's vertex colour (COLOR_0) carries the "fold" gradient of the diagonal.
const q = new URLSearchParams(location.search);
const look = {
  transmission: 1,
  roughness: +(q.get('ro') ?? 0.04),          // liquid glass: clear
  dispersion: +(q.get('disp') ?? 4),           // coloured fringe on the lensing edges
  envMapIntensity: +(q.get('env') ?? 1.0),
};
// v4: lighter than the site's 1.65 / .72, so the glass reads as clear.
const BRIGHT = +(q.get('br') ?? 1.35), SAT = +(q.get('sat') ?? 1.0), MILK = +(q.get('milk') ?? 0.045);
// Polished skin, frosted body (v3): the flat of the band blurs the halo, the
// lensing bezel (and the sphere's rim) stays sharp. Same rule as Blender's
// "frost" attribute, rebuilt from the UVs with the ribbon's bezel_uv extras.
const EDGE_RO = +(q.get('edge') ?? 0.02), FROST_RO = +(q.get('frost') ?? 0.1);
function frostGLSL(extras) {
  if (!extras.bezel_uv) return 'smoothstep(.25, .85, abs(normal.z))';      // the sphere
  const [w, span, bezel, bmin] = extras.bezel_uv.map((x) => x.toFixed(4));
  return `smoothstep(.6, 1., max(${bmin}, sqrt(max(1. - pow(1. - clamp(min(min(1. - vUv.y, vUv.y) * ${w},
    min(vUv.x, 1. - vUv.x) * ${span}) / ${bezel}, 0., 1.), 2.), 0.))))`;
}
// glint: the soft light band across the middle of the diagonal, placed with
// the ribbon's extras (s = a·u + b·v + c along the strip; glTF flips v).
function siteGlass(shader, extras) {
  const [a, b, c] = extras.s_from_uv ?? [0, 0, 1e9];
  const f = (x) => x.toFixed(4);
  shader.defines = { ...shader.defines, USE_UV: '' };
  shader.fragmentShader = shader.fragmentShader.replace('#include <lights_physical_fragment>',
    `roughnessFactor = mix(${EDGE_RO.toFixed(3)}, ${FROST_RO.toFixed(3)}, ${frostGLSL(extras)});
    #include <lights_physical_fragment>`);
  shader.fragmentShader = shader.fragmentShader.replace('#include <transmission_fragment>',
    THREE.ShaderChunk.transmission_fragment.replace(
      'vec3 pos = vWorldPosition;',
      'material.diffuseColor = mix(vec3(1.), material.diffuseColor, .55);  // fold gradient, softened\n\tvec3 pos = vWorldPosition;').replace(
      'material.transmissionAlpha = mix(',
      `{
        vec3 c = pow(max(transmitted.rgb, 0.), vec3(1. / 2.2)) * ${BRIGHT.toFixed(3)};
        c = mix(vec3(dot(c, vec3(.2126, .7152, .0722))), c, ${SAT.toFixed(3)});
        c = mix(c, vec3(.62, .95, .97) * material.diffuseColor, ${MILK.toFixed(3)});
        float s = ${f(a)} * vUv.x + ${f(b)} * (1. - vUv.y) + ${f(c)};
        float distanceToGlint = (s - ${f(extras.glint_s ?? 0)}) / ${f(extras.glint_width ?? 1)};
        float g = exp(-distanceToGlint * distanceToGlint);
        c = mix(c, vec3(.93, 1., .98), .5 * g);
        transmitted.rgb = pow(c, vec3(2.2));
      }
      material.transmissionAlpha = mix(`));
}
if(mode !== 'png') new GLTFLoader().load('../../assets/brand/3d/skilli-logo.glb', (gltf) => {
  gltf.scene.traverse((o) => {
    if (o.isMesh) {
      Object.assign(o.material, look);
      // The sphere: same glass, slightly softer, as in Blender.
      if (o.name === 'skilli_dot') Object.assign(o.material, { roughness: 0.3, specularIntensity: 0.45, clearcoatRoughness: 0.35, clearcoat: 0.4 });
      o.material = o.material.clone();
      o.material.onBeforeCompile = (sh) => siteGlass(sh, o.userData);
      o.material.customProgramCacheKey = () => o.name;
    }
  });
  logo.add(gltf.scene);
  document.body.dataset.ready = '1'; document.querySelector('#status').textContent=''; sync();
}, undefined, fail);

if(mode === 'png') new THREE.TextureLoader().load('../../assets/brand/3d/skilli-mark@2x.png', texture => {
 texture.colorSpace=THREE.SRGBColorSpace;
 const mark=new THREE.Mesh(new THREE.PlaneGeometry(2.7,2.64),new THREE.MeshBasicMaterial({map:texture,transparent:true,depthWrite:false}));
 mark.position.set(camera.position.x,camera.position.y,0);scene.add(mark);
 document.body.dataset.ready='1';document.querySelector('#status').textContent='';sync();
},undefined,fail);
function fail(){failed=true;document.querySelector('#status').textContent='3D unavailable. PNG fallback.';document.querySelector('#fallback').hidden=false;renderer?.setAnimationLoop(null);}
renderer.domElement.addEventListener('webglcontextlost',e=>{e.preventDefault();fail()});
function resize() {
  const w = innerWidth, h = innerHeight, s = Math.min(w, h);
  renderer.setSize(w, h);
  const hw = FRAME * w / s / 2, hh = FRAME * h / s / 2;
  Object.assign(camera, { left: -hw, right: hw, top: hh, bottom: -hh });
  camera.updateProjectionMatrix();
  halo.scale.set(hw * 2.2, hh * 2.2, 1);
}
addEventListener('resize', resize);
resize();

const reduce = matchMedia('(prefers-reduced-motion: reduce)');
const target = { x: 0, y: 0 };
const pointerRotation = { x: 0, y: 0 };
let tiltSource = 'pointer';
function phoneTilt() {
  return innerWidth <= 700 || matchMedia('(pointer: coarse)').matches;
}
function onOrient(event) {
  if (reduce.matches || (event.beta == null && event.gamma == null)) return;
  const next = tiltFromOrientation(event.beta, event.gamma);
  target.x = next.x;
  target.y = next.y;
  tiltSource = 'orientation';
}
const iosMotionPrompt = typeof DeviceOrientationEvent?.requestPermission === 'function';
if (!reduce.matches && (phoneTilt() || iosMotionPrompt)) {
  tiltSource = 'idle';
  addEventListener('deviceorientation', onOrient);
  addEventListener('deviceorientationabsolute', onOrient);
}
addEventListener('pointermove', (e) => {
  if((mode !== 'tilt' && !isScroll) || reduce.matches || tiltSource !== 'pointer')return;
  target.y = (e.clientX / innerWidth - 0.5) * 0.35;   // yaw, ±10°
  target.x = (e.clientY / innerHeight - 0.5) * 0.2;   // pitch, ±6°
});
addEventListener('pointerleave',()=>{if(tiltSource==='pointer'){target.x=0;target.y=0}});
let last = performance.now(), visible=true;
function tick(now) {
  const dt = Math.min((now - last) / 1000, 0.05); last = now;
  if (!reduce.matches) {
    halo.material.uniforms.t.value += dt;
    if (tiltSource === 'idle') {
      const t = halo.material.uniforms.t.value;
      target.y = Math.sin(t * 0.32) * TILT_YAW * 0.28;
      target.x = Math.cos(t * 0.21) * TILT_PITCH * 0.28;
    }
    pointerRotation.y += (target.y - pointerRotation.y) * 0.06;
    pointerRotation.x += (target.x - pointerRotation.x) * 0.06;
    logo.rotation.y = pointerRotation.y;
    logo.rotation.x = pointerRotation.x;
  }
  applyScroll();
  renderer.render(scene, camera);
}
function sync(){if(failed)return;renderer.setAnimationLoop(null);last=performance.now();applyScroll();renderer.render(scene,camera);if(visible&&!document.hidden&&!reduce.matches&&params.get('pause')!=='1')renderer.setAnimationLoop(tick);}
const observer=new IntersectionObserver(entries=>{visible=entries[0].isIntersecting;sync()});observer.observe(renderer.domElement);
reduce.addEventListener('change',sync);document.addEventListener('visibilitychange',sync);
addEventListener('resize',sync);sync();
addEventListener('pagehide',()=>{renderer.setAnimationLoop(null);observer.disconnect();scene.traverse(o=>{o.geometry?.dispose();if(o.material){for(const m of [].concat(o.material)){m.map?.dispose();m.dispose()}}});scene.environment?.dispose();renderer.dispose()});
