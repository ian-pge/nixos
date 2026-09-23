import './style.css';
import * as THREE from 'three';
import {OrbitControls} from 'three/addons/controls/OrbitControls.js';
import {RoomEnvironment} from 'three/addons/environments/RoomEnvironment.js';
import {makeGlass, WORLD_SCALE, type ViewerProfile} from './geometry.ts';
import {PRESETS, dimensions, sampleSurface, clamp, type Shape} from './profile.ts';
import {pebbleRimWidth, samplePebbleHeight} from './pebble.ts';
import {cushionProfile} from './cushion.ts';
import provenance from './profile-source.json';

document.querySelector<HTMLDivElement>('#app')!.innerHTML = `
<main class="shell">
  <header class="masthead">
    <div><div class="eyebrow">Atelier local / Three.js</div><h1>Le verre, en volume.</h1>
      <p class="subtitle">Un dessus plus doux, dans le même contour.</p></div>
    <div class="status">Réglages du visualiseur seulement</div>
  </header>
  <div class="workspace">
    <section class="viewport" aria-label="Visualisation du verre">
      <div class="stage" id="stage">
        <div class="stage-top"><div class="stage-title" id="model-title">Lanceur d’applications</div><div class="stage-meta" id="model-meta"></div></div>
        <div class="scale-badge" id="scale-badge"></div>
        <div class="profile-switch" aria-label="Comparer les volumes">
          <button data-profile="cushion" aria-pressed="true">Coussin · widgets</button>
          <button data-profile="pebble" aria-pressed="false">Galet précédent</button>
        </div>
        <canvas id="scene" aria-label="Vue 3D interactive : glisser pour tourner, molette pour zoomer" tabindex="0"></canvas>
        <nav class="viewbar" aria-label="Angle de vue">
          <button data-view="perspective" aria-pressed="true">Perspective</button>
          <button data-view="top" aria-pressed="false">Dessus</button>
          <button data-view="profile" aria-pressed="false">Profil</button>
          <button data-view="reset" title="Recentrer l’objet">↺</button>
        </nav>
        <div class="gesture">Glisser : tourner · Molette : zoomer · Clic droit : déplacer</div>
        <div class="error" id="error" role="alert" hidden><h2>La 3D n’a pas pu démarrer.</h2><p id="error-detail"></p></div>
      </div>
      <div class="hint"><span><strong>Une seule surface.</strong> La sélection est une teinte, pas une autre vitre.</span><span id="render-status">Initialisation…</span></div>
    </section>
    <aside class="controls" aria-label="Réglages du visualiseur">
      <section class="card">
        <div class="card-head"><h2>Géométrie</h2><span class="step">01 / FORME</span></div>
        <div class="segmented" aria-label="Forme du widget">
          <button data-preset="launcher" aria-pressed="true">Lanceur</button>
          <button data-preset="capsule" aria-pressed="false">Capsule</button>
          <button data-preset="calendar" aria-pressed="false">Calendrier</button>
        </div>
        <label class="range"><span>Largeur <output id="width-value"></output></span><input id="width" aria-label="Largeur" type="range" min="80" max="800" step="1" value="480"></label>
        <label class="range"><span>Hauteur <output id="height-value"></output></span><input id="height" aria-label="Hauteur" type="range" min="36" max="650" step="1" value="398"></label>
        <label class="range"><span>Rayon des coins <output id="radius-value"></output></span><input id="radius" aria-label="Rayon des coins" type="range" min="1" max="199" step="1" value="18"></label>
        <div class="scale-actions"><button class="text-button" id="tight-corners">Tester des coins serrés · 2 px</button></div>
        <p class="small-note">Dimensions en pixels logiques. Le lanceur réel peut être plus étroit selon la place disponible.</p>
      </section>
      <section class="card">
        <div class="card-head"><h2>Lire le relief</h2><span class="step">02 / SURFACE</span></div>
        <div class="segmented" aria-label="Matériau de visualisation">
          <button data-material="glass" aria-pressed="true">Verre</button>
          <button data-material="matte" aria-pressed="false">Mat</button>
          <button data-material="wire" aria-pressed="false">Maillage</button>
        </div>
        <label class="range"><span>Échelle verticale <output id="depth-value"></output></span><input id="depth" aria-label="Échelle verticale" type="range" min="2" max="100" step="1" value="8"></label>
        <div class="scale-actions"><button class="text-button" id="presentation">Vue lisible ×0,08</button><button class="text-button" id="raw">Échelle verticale ×1</button></div>
        <p class="small-note">Même hauteur maximale pour comparer les formes. Ce ne sont pas des millimètres ; seul l’axe vertical est mis à l’échelle ici.</p>
        <div class="checks">
          <label class="check"><input type="checkbox" id="cut">Coupe centrale</label>
          <label class="check"><input type="checkbox" id="selection" checked>Teinte de sélection</label>
          <label class="check"><input type="checkbox" id="base" checked>Fond plat illustratif</label>
        </div>
      </section>
      <section class="card">
        <div class="card-head"><h2>Du bord au centre</h2><span class="step">03 / PROFIL</span></div>
        <svg class="profile" viewBox="0 0 264 108" role="img" aria-label="Coupe du relief au centre">
          <path class="profile-grid" d="M10 27H254 M10 58H254 M10 89H254"/><path id="profile-curve" class="profile-fill"/>
        </svg>
        <div class="legend"><span>BORD</span><span>HAUTEUR RELATIVE</span><span>BORD</span></div>
        <div class="divider"></div>
        <label class="check" for="join">Profil de surface</label>
        <select id="join" style="margin-top:9px"><option value="cushion">Dôme coussin · widgets</option><option value="pebble">Galet précédent · 0.4.0</option><option value="smooth">Profil précédent · 0.2.5</option><option value="legacy">Ancien shader · avant lissage</option></select>
        <dl class="readouts"><div><dt id="rim-label">Bord uniforme</dt><dd id="bevel-value"></dd></div><div><dt>Hauteur de comparaison</dt><dd id="peak-value"></dd></div></dl>
        <p class="small-note" id="join-note"></p>
      </section>
    </aside>
  </div>
  <footer>
    <details><summary>Ce que cette vue représente</summary><p>« Coussin » est le modèle validé pour les widgets : le contour rectangulaire reste identique, mais l’influence de ses coins s’atténue en remontant vers le sommet. Le compositeur en échantillonne le relief et ses dérivées dans un champ GPU mis en cache. Les épaules ne sont plus contraintes à une même hauteur à distance égale du bord. « Galet précédent » archive le modèle 0.4.0. Le menu propose aussi le profil 0.2.5 et son raccord avant lissage. Tous gardent le même contour et la même hauteur maximale pour comparer les volumes. La hauteur est réduite par défaut ; ×1 montre les valeurs mathématiques, pas des millimètres. Le fond plat, l’éclairage et le matériau Three.js sont illustratifs : ils ne reproduisent pas le rendu du bureau. Aucun réglage ici ne modifie ta barre.</p></details>
    <span id="provenance-info"></span>
  </footer>
</main>`;

const element = <T extends HTMLElement = HTMLElement>(id: string) => document.getElementById(id) as T;
const input = (id: string) => element<HTMLInputElement>(id);
const canvas = element<HTMLCanvasElement>('scene');
const stage = element('stage');
let shape: Shape = {...PRESETS.launcher}, heightScale = 0.08, join: ViewerProfile = 'cushion';
let materialMode = 'glass', preset = 'launcher';
let renderer: THREE.WebGLRenderer;

function showError(message: string) {
  element('error').hidden = false;
  element('error-detail').textContent = message;
  canvas.dataset.ready = 'error';
}

try {
  renderer = new THREE.WebGLRenderer({canvas, antialias: true, alpha: true, powerPreference: 'low-power'});
  renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5));
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.35;
  renderer.localClippingEnabled = true;
  renderer.setClearColor(0x000000, 0);
  setup(renderer);
} catch (error) {
  showError('WebGL 2 est nécessaire. Essaie un navigateur avec l’accélération graphique activée. ' + String(error));
}

function setup(renderer: THREE.WebGLRenderer) {
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(36, 1, 0.01, 500);
  const controls = new OrbitControls(camera, canvas);
  // Stop drawing immediately when interaction stops (including slow/software
  // GPUs). Frame-based inertia would keep an otherwise idle viewer repainting.
  controls.enableDamping = false;
  controls.minDistance = 0.2;
  controls.maxPolarAngle = Math.PI - 0.01;
  controls.listenToKeyEvents(canvas);
  const environment = new RoomEnvironment();
  const pmrem = new THREE.PMREMGenerator(renderer);
  const envMap = pmrem.fromScene(environment, 0.07);
  scene.environment = envMap.texture;
  environment.dispose();
  pmrem.dispose();
  scene.add(new THREE.HemisphereLight(0xe5f5ef, 0x334a59, 2.4));
  const key = new THREE.DirectionalLight(0xf7f9f1, 3);
  key.position.set(-4, 7, 5);
  scene.add(key);
  const fill = new THREE.DirectionalLight(0x9cc6d6, 1.1);
  fill.position.set(6, 4, -4);
  scene.add(fill);

  const floor = new THREE.Mesh(new THREE.PlaneGeometry(200, 200), new THREE.MeshStandardMaterial({color: 0xd5dfe0, roughness: 1}));
  floor.rotation.x = -Math.PI / 2;
  floor.position.y = -0.035;
  scene.add(floor);
  const grid = new THREE.GridHelper(18, 72, 0x91a7a9, 0xb4c2c3);
  grid.position.y = -0.03;
  scene.add(grid);

  const clipping = new THREE.Plane(new THREE.Vector3(0, 0, -1), 0);
  const glass = new THREE.MeshPhysicalMaterial({color: 0xc7d7da, metalness: 0, roughness: 0.12,
    transmission: 0.97, thickness: 0.4, ior: 1.5, attenuationColor: new THREE.Color(0x334e58),
    attenuationDistance: 1.1, envMapIntensity: 0.8, vertexColors: true, side: THREE.FrontSide});
  const matte = new THREE.MeshStandardMaterial({color: 0x314a47, roughness: 0.72, metalness: 0,
    envMapIntensity: 0.28, vertexColors: true, side: THREE.DoubleSide});
  const wire = new THREE.MeshBasicMaterial({color: 0x254d50, wireframe: true, transparent: true, opacity: 0.28});
  const baseMaterial = new THREE.MeshPhysicalMaterial({color: 0x718183, transmission: 0.7, roughness: 0.25,
    thickness: 0.1, side: THREE.FrontSide, opacity: 1});
  const cutMaterial = new THREE.MeshStandardMaterial({color: 0x8bbdb0, roughness: 0.75, side: THREE.DoubleSide});
  const lineMaterial = new THREE.LineBasicMaterial({color: 0x2e7565});
  const top = new THREE.Mesh<THREE.BufferGeometry, THREE.Material>(new THREE.BufferGeometry(), glass);
  const bottom = new THREE.Mesh(new THREE.BufferGeometry(), baseMaterial);
  const section = new THREE.Mesh(new THREE.BufferGeometry(), cutMaterial);
  const cutLine = new THREE.Line(new THREE.BufferGeometry(), lineMaterial);
  scene.add(top, bottom, section, cutLine);

  let frame = 0, count = 0, pendingGeometry = false;
  let activeView = 'perspective';
  function requestRender() {
    if (!frame && !document.hidden) frame = requestAnimationFrame(render);
  }
  function render() {
    frame = 0;
    if (pendingGeometry) { pendingGeometry = false; rebuild(); }
    controls.update();
    floor.visible = grid.visible = camera.position.y >= 0;
    renderer.render(scene, camera);
    canvas.dataset.frames = String(++count);
    canvas.dataset.ready = 'true';
  }
  controls.addEventListener('change', requestRender);
  controls.addEventListener('start', () => setViewState('free'));

  function updateMaterial() {
    const cut = input('cut').checked;
    for (const material of [glass, matte, wire, baseMaterial]) {
      material.clippingPlanes = cut ? [clipping] : [];
      material.needsUpdate = true;
    }
    top.material = materialMode === 'matte' ? matte : materialMode === 'wire' ? wire : glass;
    bottom.visible = input('base').checked && materialMode !== 'wire';
    section.visible = cut && input('base').checked;
    cutLine.visible = cut;
    canvas.dataset.material = materialMode;
    canvas.dataset.cut = String(cut);
    requestRender();
  }

  function rebuild() {
    const meshes = makeGlass(shape, heightScale, join, input('selection').checked);
    for (const [mesh, geometry] of [[top, meshes.surface], [bottom, meshes.base], [section, meshes.section], [cutLine, meshes.edge]] as const) {
      mesh.geometry.dispose();
      mesh.geometry = geometry;
    }
    const d = dimensions(shape);
    element('width-value').textContent = `${shape.width} px`;
    element('height-value').textContent = `${shape.height} px`;
    element('radius-value').textContent = `${shape.radius} px`;
    element('depth-value').textContent = `×${heightScale.toFixed(2).replace('.', ',')}`;
    element('scale-badge').textContent = `Axe vertical ×${heightScale.toFixed(2).replace('.', ',')}`;
    element('model-meta').textContent = `${shape.width} × ${shape.height} px · coins ${shape.radius} px`;
    element('model-title').textContent = preset === 'launcher' ? 'Lanceur d’applications' : preset === 'capsule' ? 'Capsule de la barre' : preset === 'calendar' ? 'Panneau calendrier' : 'Forme personnalisée';
    element('rim-label').textContent = join === 'cushion' ? 'Dessus' : join === 'pebble' ? 'Bord uniforme' : 'Bande arrondie';
    element('bevel-value').textContent = join === 'cushion' ? 'Dôme continu'
      : `${(join === 'pebble' ? pebbleRimWidth(shape) : d.bevelWidth).toFixed(1).replace('.', ',')} px`;
    element('peak-value').textContent = `${d.centreHeight.toFixed(1).replace('.', ',')} u.`;
    element('join-note').textContent = join === 'cushion'
      ? 'Profil des widgets : coins serrés au contour, influence des coins atténuée vers le sommet. Compare en mode Mat, avec le même éclairage.'
      : join === 'pebble'
      ? 'Galet précédent (0.4.0) : bande extérieure uniforme, mais courbure plus concentrée près des coins.'
      : join === 'smooth' ? 'Profil précédent (0.2.5). Son raccord est lissé, mais les épaules n’ont pas la même hauteur.'
      : 'Ancien raccord : la pente est continue, mais la courbure change brusquement.';
    element('provenance-info').textContent = join === 'cushion' ? 'Coussin validé · parité GPU contrôlée · Rendu à la demande'
      : join === 'pebble' ? 'Galet précédent archivé · 0.4.0 · Rendu à la demande'
      : `Profil précédent archivé · ${provenance.sha256.slice(0, 12)} · Rendu à la demande`;
    document.querySelectorAll<HTMLButtonElement>('[data-profile]').forEach(button =>
      button.setAttribute('aria-pressed', String(button.dataset.profile === join)));
    element('render-status').textContent = `${Math.round(meshes.surface.getIndex()!.count / 3000)} k triangles · au repos entre les interactions`;
    const points = Array.from({length: 241}, (_, i) => {
      const x = -shape.width / 2 + shape.width * i / 240;
      const h = join === 'cushion' ? cushionProfile(shape).sectionHeight(x)
        : join === 'pebble' ? samplePebbleHeight(x, 0, shape) : sampleSurface(x, 0, shape, join).height;
      return `${(12 + i).toFixed(2)},${(91 - h / d.centreHeight * 72).toFixed(2)}`;
    });
    element('profile-curve').setAttribute('d', `M12,91 L${points.join(' L')} L252,91 Z`);
    canvas.dataset.join = join;
    canvas.dataset.heightScale = String(heightScale);
    canvas.dataset.preset = preset;
    canvas.dataset.vertices = String(meshes.surface.getAttribute('position').count);
    canvas.dataset.peak = String(d.centreHeight);
  }

  function setViewState(view: string) {
    activeView = view;
    document.querySelectorAll<HTMLButtonElement>('[data-view]').forEach(button =>
      button.setAttribute('aria-pressed', String(button.dataset.view === view)));
  }
  function fit(view = activeView === 'free' ? 'perspective' : activeView) {
    const peak = dimensions(shape).centreHeight * heightScale * WORLD_SCALE;
    const size = Math.max(shape.width * WORLD_SCALE, shape.height * WORLD_SCALE, peak);
    const target = new THREE.Vector3(0, peak * 0.38, 0);
    const distance = size * (camera.aspect < 1 ? 2.2 / camera.aspect : 2.05);
    const direction = view === 'top' ? new THREE.Vector3(0.0001, 1, 0.0001)
      : view === 'profile' ? new THREE.Vector3(0, 0.06, 1) : new THREE.Vector3(0.8, 0.8, 1.1);
    camera.position.copy(target).add(direction.normalize().multiplyScalar(distance));
    controls.target.copy(target);
    controls.maxDistance = size * 8;
    controls.update();
    setViewState(view);
    requestRender();
  }

  document.querySelectorAll<HTMLButtonElement>('[data-preset]').forEach(button => button.addEventListener('click', () => {
    preset = button.dataset.preset!;
    shape = {...PRESETS[preset]};
    for (const key of ['width', 'height', 'radius'] as const) input(key).value = String(shape[key]);
    input('radius').max = String(Math.floor(Math.min(shape.width, shape.height) / 2));
    document.querySelectorAll<HTMLButtonElement>('[data-preset]').forEach(b => b.setAttribute('aria-pressed', String(b === button)));
    rebuild(); fit();
  }));
  for (const key of ['width', 'height', 'radius'] as const) input(key).addEventListener('input', () => {
    shape[key] = Number(input(key).value);
    shape.radius = clamp(shape.radius, 1, Math.min(shape.width, shape.height) / 2);
    input('radius').max = String(Math.floor(Math.min(shape.width, shape.height) / 2));
    input('radius').value = String(shape.radius);
    preset = 'custom';
    document.querySelectorAll('[data-preset]').forEach(b => b.setAttribute('aria-pressed', 'false'));
    pendingGeometry = true; requestRender();
  });
  element('tight-corners').addEventListener('click', () => {
    input('radius').value = '2';
    input('radius').dispatchEvent(new Event('input'));
  });
  const changeHeight = (value: number, recenter: boolean) => {
    heightScale = value; input('depth').value = String(value * 100);
    rebuild(); if (recenter) fit(); else requestRender();
  };
  input('depth').addEventListener('input', () => changeHeight(Number(input('depth').value) / 100, true));
  element('raw').addEventListener('click', () => changeHeight(1, true));
  element('presentation').addEventListener('click', () => changeHeight(0.08, true));
  document.querySelectorAll<HTMLButtonElement>('[data-material]').forEach(button => button.addEventListener('click', () => {
    materialMode = button.dataset.material!;
    document.querySelectorAll('[data-material]').forEach(b => b.setAttribute('aria-pressed', String(b === button)));
    updateMaterial();
  }));
  document.querySelectorAll<HTMLButtonElement>('[data-view]').forEach(button => button.addEventListener('click', () => fit(button.dataset.view === 'reset' ? 'perspective' : button.dataset.view)));
  input('cut').addEventListener('change', updateMaterial);
  input('base').addEventListener('change', updateMaterial);
  input('selection').addEventListener('change', () => { pendingGeometry = true; requestRender(); });
  function chooseProfile(value: ViewerProfile) {
    join = value;
    element<HTMLSelectElement>('join').value = value;
    pendingGeometry = true; requestRender();
  }
  element<HTMLSelectElement>('join').addEventListener('change', event => chooseProfile((event.target as HTMLSelectElement).value as ViewerProfile));
  document.querySelectorAll<HTMLButtonElement>('[data-profile]').forEach(button =>
    button.addEventListener('click', () => chooseProfile(button.dataset.profile as ViewerProfile)));
  const resize = new ResizeObserver(() => {
    const {width, height} = stage.getBoundingClientRect();
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
    renderer.setSize(width, height, false);
    requestRender();
  });
  resize.observe(stage);
  document.addEventListener('visibilitychange', () => {
    if (document.hidden && frame) { cancelAnimationFrame(frame); frame = 0; }
    else requestRender();
  });
  canvas.addEventListener('webglcontextlost', event => { event.preventDefault(); showError('Le contexte graphique a été perdu. Recharge cette page pour relancer le visualiseur.'); });
  rebuild(); updateMaterial();
  const rect = stage.getBoundingClientRect();
  camera.aspect = rect.width / rect.height; camera.updateProjectionMatrix();
  renderer.setSize(rect.width, rect.height, false);
  fit();
  window.addEventListener('pagehide', event => {
    if (event.persisted) return;
    cancelAnimationFrame(frame); controls.dispose(); resize.disconnect();
    for (const mesh of [top, bottom, section, cutLine, floor, grid]) mesh.geometry.dispose();
    for (const material of [glass, matte, wire, baseMaterial, cutMaterial, lineMaterial]) material.dispose();
    floor.material.dispose();
    grid.material.dispose();
    envMap.dispose(); renderer.dispose();
  });
}
