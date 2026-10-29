/**
 * Praxis Linux (AIOS) — 3D Interactive WebGL Experience
 * Built with Three.js — Ultra-fluid 60fps rendering, dynamic lighting,
 * holographic glass cards, glowing AI core orb, and mouse-parallax responsiveness.
 */

(function () {
  'use strict';

  const container = document.getElementById('canvas-container');
  if (!container || typeof THREE === 'undefined') return;

  // Scene, Camera, Renderer
  const scene = new THREE.Scene();
  scene.fog = new THREE.FogExp2(0x080a0f, 0.025);

  const camera = new THREE.PerspectiveCamera(
    45,
    container.clientWidth / container.clientHeight,
    0.1,
    100
  );
  camera.position.set(0, 2.5, 9.5);

  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, powerPreference: 'high-performance' });
  renderer.setSize(container.clientWidth, container.clientHeight);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.75));
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  container.appendChild(renderer.domElement);

  // Master group for scene rotation
  const masterGroup = new THREE.Group();
  scene.add(masterGroup);

  // -------------------------------------------------------------------------
  // Lighting
  // -------------------------------------------------------------------------
  const ambientLight = new THREE.AmbientLight(0xffffff, 0.7);
  scene.add(ambientLight);

  const keyLight = new THREE.DirectionalLight(0x58e1ff, 1.4);
  keyLight.position.set(6, 10, 6);
  scene.add(keyLight);

  const rimLight = new THREE.DirectionalLight(0x8b5cf6, 1.6);
  rimLight.position.set(-6, -3, -4);
  scene.add(rimLight);

  // Screen glow point light
  const screenLight = new THREE.PointLight(0x58e1ff, 2.2, 8);
  screenLight.position.set(0, 1.8, 0.8);
  masterGroup.add(screenLight);

  // AI Core point light
  const aiGlowLight = new THREE.PointLight(0xa855f7, 3, 6);
  aiGlowLight.position.set(2.8, 1.8, 1.2);
  masterGroup.add(aiGlowLight);

  // -------------------------------------------------------------------------
  // Materials
  // -------------------------------------------------------------------------
  const chassisMaterial = new THREE.MeshStandardMaterial({
    color: 0x111622,
    metalness: 0.85,
    roughness: 0.22,
  });

  const keyboardMaterial = new THREE.MeshStandardMaterial({
    color: 0x07090e,
    metalness: 0.7,
    roughness: 0.45,
  });

  const glassMaterial = new THREE.MeshPhysicalMaterial({
    color: 0x1e293b,
    metalness: 0.1,
    roughness: 0.1,
    transparent: true,
    opacity: 0.65,
    transmission: 0.6,
    ior: 1.5,
  });

  // -------------------------------------------------------------------------
  // Laptop Construction
  // -------------------------------------------------------------------------
  const laptopGroup = new THREE.Group();
  laptopGroup.position.set(-0.6, -0.4, 0);

  // Base chassis
  const baseGeo = new THREE.BoxGeometry(4.8, 0.18, 3.4);
  const baseMesh = new THREE.Mesh(baseGeo, chassisMaterial);
  baseMesh.position.y = -0.09;
  laptopGroup.add(baseMesh);

  // Keyboard recess & keys
  const kbRecessGeo = new THREE.BoxGeometry(4.2, 0.04, 1.8);
  const kbRecess = new THREE.Mesh(kbRecessGeo, keyboardMaterial);
  kbRecess.position.set(0, 0.02, -0.4);
  laptopGroup.add(kbRecess);

  // Trackpad
  const trackpadGeo = new THREE.BoxGeometry(1.6, 0.02, 1.0);
  const trackpadMat = new THREE.MeshStandardMaterial({
    color: 0x1a2130,
    metalness: 0.4,
    roughness: 0.3,
  });
  const trackpad = new THREE.Mesh(trackpadGeo, trackpadMat);
  trackpad.position.set(0, 0.01, 1.05);
  laptopGroup.add(trackpad);

  // Screen Hinge & Lid
  const lidGroup = new THREE.Group();
  lidGroup.position.set(0, 0, -1.7); // hinge pivot point
  lidGroup.rotation.x = THREE.MathUtils.degToRad(20); // tilted 110 degrees relative to base

  // Lid outer shell
  const lidGeo = new THREE.BoxGeometry(4.8, 3.2, 0.12);
  const lidMesh = new THREE.Mesh(lidGeo, chassisMaterial);
  lidMesh.position.set(0, 1.6, 0);
  lidGroup.add(lidMesh);

  // Screen display canvas texture
  const screenCanvas = document.createElement('canvas');
  screenCanvas.width = 1024;
  screenCanvas.height = 680;
  const ctx = screenCanvas.getContext('2d');

  function updateScreenCanvas() {
    // Background gradient
    const grad = ctx.createLinearGradient(0, 0, 1024, 680);
    grad.addColorStop(0, '#0c101a');
    grad.addColorStop(0.5, '#17192b');
    grad.addColorStop(1, '#090c14');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, 1024, 680);

    // Glowing nebula circles
    ctx.fillStyle = 'rgba(139, 92, 246, 0.18)';
    ctx.beginPath();
    ctx.arc(300, 340, 240, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = 'rgba(88, 225, 255, 0.15)';
    ctx.beginPath();
    ctx.arc(750, 280, 200, 0, Math.PI * 2);
    ctx.fill();

    // Top bar
    ctx.fillStyle = 'rgba(12, 15, 24, 0.85)';
    ctx.fillRect(0, 0, 1024, 38);
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.08)';
    ctx.strokeRect(0, 0, 1024, 38);

    // Vitals in top bar
    ctx.fillStyle = '#58e1ff';
    ctx.font = 'bold 15px "JetBrains Mono", monospace';
    ctx.fillText('PRAXIS AIOS  ::  CPU 4%  |  RAM 2.4G  |  VRAM 1.8G  |  120Hz', 24, 25);
    ctx.fillStyle = '#cbd5e1';
    ctx.fillText('⚡ 100%   📶 Wi-Fi 6   22:30', 820, 25);

    // Windows layout preview
    ctx.fillStyle = 'rgba(20, 27, 44, 0.7)';
    ctx.strokeStyle = 'rgba(88, 225, 255, 0.4)';
    ctx.lineWidth = 2;
    ctx.roundRect(40, 70, 580, 520, 12);
    ctx.fill();
    ctx.stroke();

    ctx.fillStyle = '#ffffff';
    ctx.font = 'bold 20px "Inter", sans-serif';
    ctx.fillText('❯ Terminal — ai "why is my laptop cool?"', 65, 115);
    ctx.fillStyle = '#94a3b8';
    ctx.font = '16px "JetBrains Mono", monospace';
    ctx.fillText('● GPU: RTX 4060 Mobile [42°C | 15W]', 65, 160);
    ctx.fillText('● Memory: ZRAM zstd compression active', 65, 195);
    ctx.fillText('● PSI Pressure: 0.00 (Zero freezes detected)', 65, 230);
    ctx.fillText('● Privacy Gate: 100% Local Inference (CUDA)', 65, 265);

    // Second tiled window
    ctx.fillStyle = 'rgba(27, 24, 46, 0.7)';
    ctx.strokeStyle = 'rgba(139, 92, 246, 0.4)';
    ctx.roundRect(645, 70, 340, 520, 12);
    ctx.fill();
    ctx.stroke();

    ctx.fillStyle = '#c4b5fd';
    ctx.font = 'bold 18px "Inter", sans-serif';
    ctx.fillText('Praxis Assistant', 670, 115);
    ctx.fillStyle = '#94a3b8';
    ctx.font = '14px "Inter", sans-serif';
    ctx.fillText('Super+H: Voice Dictate', 670, 160);
    ctx.fillText('Super+I: Sovereign AI', 670, 195);
    ctx.fillText('Super+G: Game Mode On', 670, 230);
  }

  updateScreenCanvas();
  const screenTexture = new THREE.CanvasTexture(screenCanvas);

  const screenMeshGeo = new THREE.PlaneGeometry(4.5, 2.9);
  const screenMeshMat = new THREE.MeshBasicMaterial({
    map: screenTexture,
  });
  const screenMesh = new THREE.Mesh(screenMeshGeo, screenMeshMat);
  screenMesh.position.set(0, 1.6, 0.07);
  lidGroup.add(screenMesh);

  laptopGroup.add(lidGroup);
  masterGroup.add(laptopGroup);

  // -------------------------------------------------------------------------
  // Floating Holographic AI Core Orb
  // -------------------------------------------------------------------------
  const orbGroup = new THREE.Group();
  orbGroup.position.set(3.0, 1.8, 1.0);

  const innerSphereGeo = new THREE.SphereGeometry(0.7, 32, 32);
  const innerSphereMat = new THREE.MeshStandardMaterial({
    color: 0x8b5cf6,
    emissive: 0x6d28d9,
    emissiveIntensity: 0.8,
    roughness: 0.2,
    metalness: 0.5,
  });
  const innerSphere = new THREE.Mesh(innerSphereGeo, innerSphereMat);
  orbGroup.add(innerSphere);

  const wireGeo = new THREE.IcosahedronGeometry(0.95, 1);
  const wireMat = new THREE.MeshBasicMaterial({
    color: 0x58e1ff,
    wireframe: true,
    transparent: true,
    opacity: 0.45,
  });
  const wireOrb = new THREE.Mesh(wireGeo, wireMat);
  orbGroup.add(wireOrb);

  // Orbiting ring
  const ringGeo = new THREE.RingGeometry(1.2, 1.26, 64);
  const ringMat = new THREE.MeshBasicMaterial({
    color: 0x38bdf8,
    side: THREE.DoubleSide,
    transparent: true,
    opacity: 0.6,
  });
  const ringMesh = new THREE.Mesh(ringGeo, ringMat);
  ringMesh.rotation.x = Math.PI / 3;
  orbGroup.add(ringMesh);

  masterGroup.add(orbGroup);

  // -------------------------------------------------------------------------
  // Floating Glass Cards (Holographic UI)
  // -------------------------------------------------------------------------
  const cardGeo = new THREE.BoxGeometry(2.0, 1.2, 0.05);
  const cardMat1 = glassMaterial.clone();
  cardMat1.color = new THREE.Color(0x38bdf8);
  const floatCard1 = new THREE.Mesh(cardGeo, cardMat1);
  floatCard1.position.set(-3.2, 2.0, 0.5);
  floatCard1.rotation.y = THREE.MathUtils.degToRad(24);
  masterGroup.add(floatCard1);

  const cardMat2 = glassMaterial.clone();
  cardMat2.color = new THREE.Color(0xa855f7);
  const floatCard2 = new THREE.Mesh(cardGeo, cardMat2);
  floatCard2.position.set(2.8, -0.6, 1.8);
  floatCard2.rotation.y = THREE.MathUtils.degToRad(-18);
  floatCard2.rotation.x = THREE.MathUtils.degToRad(-10);
  masterGroup.add(floatCard2);

  // -------------------------------------------------------------------------
  // Starfield & Ambient Dust Particles
  // -------------------------------------------------------------------------
  const particleCount = 240;
  const particleGeo = new THREE.BufferGeometry();
  const particleCoords = new Float32Array(particleCount * 3);

  for (let i = 0; i < particleCount * 3; i += 3) {
    particleCoords[i] = (Math.random() - 0.5) * 18;
    particleCoords[i + 1] = (Math.random() - 0.5) * 14;
    particleCoords[i + 2] = (Math.random() - 0.5) * 14;
  }
  particleGeo.setAttribute('position', new THREE.BufferAttribute(particleCoords, 3));

  const particleMat = new THREE.PointsMaterial({
    color: 0x8b5cf6,
    size: 0.06,
    transparent: true,
    opacity: 0.65,
    blending: THREE.AdditiveBlending,
  });
  const particleSystem = new THREE.Points(particleGeo, particleMat);
  scene.add(particleSystem);

  // -------------------------------------------------------------------------
  // Parallax & Mouse Interactivity
  // -------------------------------------------------------------------------
  let targetRotationX = 0;
  let targetRotationY = 0;
  let isPointerDown = false;
  let prevPointerX = 0;
  let prevPointerY = 0;

  function onPointerMove(e) {
    const rect = container.getBoundingClientRect();
    const x = (e.clientX - rect.left) / rect.width - 0.5;
    const y = (e.clientY - rect.top) / rect.height - 0.5;

    if (isPointerDown) {
      const deltaX = e.clientX - prevPointerX;
      const deltaY = e.clientY - prevPointerY;
      targetRotationY += deltaX * 0.005;
      targetRotationX += deltaY * 0.005;
      prevPointerX = e.clientX;
      prevPointerY = e.clientY;
    } else {
      targetRotationY = x * 0.45;
      targetRotationX = y * 0.35;
    }
  }

  function onPointerDown(e) {
    isPointerDown = true;
    prevPointerX = e.clientX;
    prevPointerY = e.clientY;
  }

  function onPointerUp() {
    isPointerDown = false;
  }

  container.addEventListener('pointermove', onPointerMove);
  container.addEventListener('pointerdown', onPointerDown);
  window.addEventListener('pointerup', onPointerUp);

  // Resize Handling
  window.addEventListener('resize', () => {
    if (!container) return;
    const width = container.clientWidth;
    const height = container.clientHeight;
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
    renderer.setSize(width, height);
  });

  // -------------------------------------------------------------------------
  // Animation Loop
  // -------------------------------------------------------------------------
  let clock = new THREE.Clock();

  function animate() {
    requestAnimationFrame(animate);

    const elapsed = clock.getElapsedTime();

    // Smooth lerp parallax for the master group
    masterGroup.rotation.y += (targetRotationY - masterGroup.rotation.y) * 0.06;
    masterGroup.rotation.x += (targetRotationX - masterGroup.rotation.x) * 0.06;

    // Subtle gentle floating bob for the whole laptop
    laptopGroup.position.y = -0.4 + Math.sin(elapsed * 1.2) * 0.08;

    // AI Core Orb animations
    wireOrb.rotation.y = elapsed * 0.5;
    wireOrb.rotation.x = elapsed * 0.3;
    ringMesh.rotation.z = elapsed * 0.8;
    orbGroup.position.y = 1.8 + Math.sin(elapsed * 2.0) * 0.12;

    // Floating cards gentle wave
    floatCard1.position.y = 2.0 + Math.cos(elapsed * 1.5) * 0.1;
    floatCard2.position.y = -0.6 + Math.sin(elapsed * 1.4) * 0.08;

    // Slow ambient rotation of starfield
    particleSystem.rotation.y = elapsed * 0.02;

    renderer.render(scene, camera);
  }

  animate();
})();
