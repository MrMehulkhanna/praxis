/**
 * Praxis Linux (AIOS) — 3D Interactive WebGL Experience
 * Built with Three.js — Ultra-fluid 60fps rendering, dynamic lighting,
 * holographic glass cards, glowing AI core orb, interactive keyboard backlighting,
 * and mouse/touch parallax with camera preset switching.
 */

(function () {
  'use strict';

  const container = document.getElementById('canvas-container');
  if (!container || typeof THREE === 'undefined') return;

  // Scene, Camera, Renderer
  const scene = new THREE.Scene();
  scene.fog = new THREE.FogExp2(0x080a0f, 0.022);

  const camera = new THREE.PerspectiveCamera(
    45,
    container.clientWidth / container.clientHeight,
    0.1,
    100
  );
  camera.position.set(0, 2.4, 9.2);

  const renderer = new THREE.WebGLRenderer({
    antialias: true,
    alpha: true,
    powerPreference: 'high-performance'
  });
  renderer.setSize(container.clientWidth, container.clientHeight);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2.0));
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  container.appendChild(renderer.domElement);

  // Master group for scene rotation
  const masterGroup = new THREE.Group();
  scene.add(masterGroup);

  // -------------------------------------------------------------------------
  // Lighting
  // -------------------------------------------------------------------------
  const ambientLight = new THREE.AmbientLight(0xffffff, 0.75);
  scene.add(ambientLight);

  const keyLight = new THREE.DirectionalLight(0x58e1ff, 1.5);
  keyLight.position.set(6, 10, 6);
  scene.add(keyLight);

  const rimLight = new THREE.DirectionalLight(0x8b5cf6, 1.8);
  rimLight.position.set(-6, -3, -4);
  scene.add(rimLight);

  // Screen glow point light
  const screenLight = new THREE.PointLight(0x58e1ff, 2.4, 8);
  screenLight.position.set(0, 1.8, 0.9);
  masterGroup.add(screenLight);

  // AI Core point light
  const aiGlowLight = new THREE.PointLight(0xa855f7, 3.2, 7);
  aiGlowLight.position.set(2.8, 1.8, 1.2);
  masterGroup.add(aiGlowLight);

  // -------------------------------------------------------------------------
  // Materials
  // -------------------------------------------------------------------------
  const chassisMaterial = new THREE.MeshStandardMaterial({
    color: 0x101522,
    metalness: 0.88,
    roughness: 0.2,
  });

  const keyboardMaterial = new THREE.MeshStandardMaterial({
    color: 0x06080d,
    metalness: 0.75,
    roughness: 0.4,
  });

  const kbBacklightMaterial = new THREE.MeshBasicMaterial({
    color: 0x58e1ff,
    transparent: true,
    opacity: 0.28,
  });

  const glassMaterial = new THREE.MeshPhysicalMaterial({
    color: 0x1e293b,
    metalness: 0.1,
    roughness: 0.08,
    transparent: true,
    opacity: 0.68,
    transmission: 0.65,
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

  // Keyboard backlight glow plate
  const kbGlowGeo = new THREE.PlaneGeometry(4.16, 1.76);
  const kbGlowMesh = new THREE.Mesh(kbGlowGeo, kbBacklightMaterial);
  kbGlowMesh.rotation.x = -Math.PI / 2;
  kbGlowMesh.position.set(0, 0.025, -0.4);
  laptopGroup.add(kbGlowMesh);

  // Trackpad
  const trackpadGeo = new THREE.BoxGeometry(1.6, 0.02, 1.0);
  const trackpadMat = new THREE.MeshStandardMaterial({
    color: 0x192130,
    metalness: 0.45,
    roughness: 0.25,
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

  let simTick = 0;
  function updateScreenCanvas() {
    simTick++;
    // Background gradient
    const grad = ctx.createLinearGradient(0, 0, 1024, 680);
    grad.addColorStop(0, '#0a0d16');
    grad.addColorStop(0.5, '#141829');
    grad.addColorStop(1, '#080a11');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, 1024, 680);

    // Glowing nebula circles
    ctx.fillStyle = 'rgba(139, 92, 246, 0.18)';
    ctx.beginPath();
    ctx.arc(280, 320, 240, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = 'rgba(88, 225, 255, 0.16)';
    ctx.beginPath();
    ctx.arc(760, 260, 210, 0, Math.PI * 2);
    ctx.fill();

    // Top bar
    ctx.fillStyle = 'rgba(10, 13, 22, 0.9)';
    ctx.fillRect(0, 0, 1024, 40);
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.1)';
    ctx.strokeRect(0, 0, 1024, 40);

    // Vitals in top bar
    ctx.fillStyle = '#58e1ff';
    ctx.font = 'bold 15px "JetBrains Mono", monospace';
    const cpuVal = 3 + (simTick % 4);
    ctx.fillText(`PRAXIS AIOS  ::  CPU ${cpuVal}%  |  RAM 2.4G  |  VRAM 1.8G  |  120Hz`, 24, 26);
    ctx.fillStyle = '#cbd5e1';
    ctx.fillText('⚡ 100%   📶 Wi-Fi 6   22:30', 820, 26);

    // Windows layout preview — Terminal Window
    ctx.fillStyle = 'rgba(18, 24, 40, 0.76)';
    ctx.strokeStyle = 'rgba(88, 225, 255, 0.45)';
    ctx.lineWidth = 2;
    ctx.roundRect(40, 68, 580, 520, 12);
    ctx.fill();
    ctx.stroke();

    ctx.fillStyle = '#ffffff';
    ctx.font = 'bold 19px "Inter", sans-serif';
    ctx.fillText('❯ Terminal — ai "why is my laptop cool?"', 65, 110);
    ctx.fillStyle = '#94a3b8';
    ctx.font = '15px "JetBrains Mono", monospace';
    ctx.fillText('● GPU: RTX 4060 Mobile [42°C | 15W]', 65, 155);
    ctx.fillText('● Memory: ZRAM zstd compression active', 65, 190);
    ctx.fillText('● PSI Pressure: 0.00 (Zero freezes detected)', 65, 225);
    ctx.fillText('● Privacy Gate: 100% Local Inference (CUDA)', 65, 260);

    // Flashing cursor simulation
    if (Math.floor(simTick / 30) % 2 === 0) {
      ctx.fillStyle = '#58e1ff';
      ctx.fillRect(65, 300, 12, 20);
    }

    // Second tiled window — Praxis AI Assistant Card
    ctx.fillStyle = 'rgba(25, 22, 44, 0.76)';
    ctx.strokeStyle = 'rgba(139, 92, 246, 0.45)';
    ctx.roundRect(645, 68, 340, 520, 12);
    ctx.fill();
    ctx.stroke();

    ctx.fillStyle = '#c4b5fd';
    ctx.font = 'bold 18px "Inter", sans-serif';
    ctx.fillText('Praxis Assistant', 670, 110);
    ctx.fillStyle = '#94a3b8';
    ctx.font = '14px "Inter", sans-serif';
    ctx.fillText('Super+H: Voice Dictate', 670, 155);
    ctx.fillText('Super+I: Sovereign AI', 670, 190);
    ctx.fillText('Super+G: Game Mode On', 670, 225);
    ctx.fillText('Super+O: Control Center', 670, 260);
    ctx.fillText('Super+B: Widget Board', 670, 295);

    // Dock representation at bottom
    ctx.fillStyle = 'rgba(15, 20, 32, 0.85)';
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.12)';
    ctx.roundRect(362, 615, 300, 52, 16);
    ctx.fill();
    ctx.stroke();

    // Dock app icons
    const iconColors = ['#58e1ff', '#8b5cf6', '#10b981', '#f59e0b', '#ec4899'];
    iconColors.forEach((color, idx) => {
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.arc(400 + idx * 56, 641, 16, 0, Math.PI * 2);
      ctx.fill();
    });
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
    emissiveIntensity: 0.85,
    roughness: 0.18,
    metalness: 0.5,
  });
  const innerSphere = new THREE.Mesh(innerSphereGeo, innerSphereMat);
  orbGroup.add(innerSphere);

  const wireGeo = new THREE.IcosahedronGeometry(0.95, 1);
  const wireMat = new THREE.MeshBasicMaterial({
    color: 0x58e1ff,
    wireframe: true,
    transparent: true,
    opacity: 0.5,
  });
  const wireOrb = new THREE.Mesh(wireGeo, wireMat);
  orbGroup.add(wireOrb);

  // Orbiting rings (dual gyroscopic rings)
  const ringGeo1 = new THREE.RingGeometry(1.2, 1.26, 64);
  const ringMat1 = new THREE.MeshBasicMaterial({
    color: 0x38bdf8,
    side: THREE.DoubleSide,
    transparent: true,
    opacity: 0.65,
  });
  const ringMesh1 = new THREE.Mesh(ringGeo1, ringMat1);
  ringMesh1.rotation.x = Math.PI / 3;
  orbGroup.add(ringMesh1);

  const ringGeo2 = new THREE.RingGeometry(1.35, 1.4, 64);
  const ringMat2 = new THREE.MeshBasicMaterial({
    color: 0xa855f7,
    side: THREE.DoubleSide,
    transparent: true,
    opacity: 0.45,
  });
  const ringMesh2 = new THREE.Mesh(ringGeo2, ringMat2);
  ringMesh2.rotation.y = Math.PI / 3;
  orbGroup.add(ringMesh2);

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
  const particleCount = 260;
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
    size: 0.065,
    transparent: true,
    opacity: 0.7,
    blending: THREE.AdditiveBlending,
  });
  const particleSystem = new THREE.Points(particleGeo, particleMat);
  scene.add(particleSystem);

  // -------------------------------------------------------------------------
  // Parallax, Touch & Interactive Controls
  // -------------------------------------------------------------------------
  let targetRotationX = 0.08;
  let targetRotationY = -0.15;
  let isPointerDown = false;
  let prevPointerX = 0;
  let prevPointerY = 0;
  let autoSpin = true;

  function onPointerMove(e) {
    const rect = container.getBoundingClientRect();
    const clientX = e.clientX || (e.touches && e.touches[0].clientX) || 0;
    const clientY = e.clientY || (e.touches && e.touches[0].clientY) || 0;

    const x = (clientX - rect.left) / rect.width - 0.5;
    const y = (clientY - rect.top) / rect.height - 0.5;

    if (isPointerDown) {
      const deltaX = clientX - prevPointerX;
      const deltaY = clientY - prevPointerY;
      targetRotationY += deltaX * 0.005;
      targetRotationX += deltaY * 0.005;
      prevPointerX = clientX;
      prevPointerY = clientY;
    } else if (!autoSpin) {
      targetRotationY = x * 0.55;
      targetRotationX = y * 0.4;
    }
  }

  function onPointerDown(e) {
    isPointerDown = true;
    prevPointerX = e.clientX || (e.touches && e.touches[0].clientX) || 0;
    prevPointerY = e.clientY || (e.touches && e.touches[0].clientY) || 0;
  }

  function onPointerUp() {
    isPointerDown = false;
  }

  container.addEventListener('pointermove', onPointerMove);
  container.addEventListener('pointerdown', onPointerDown);
  window.addEventListener('pointerup', onPointerUp);

  // Touch Support
  container.addEventListener('touchmove', onPointerMove, { passive: true });
  container.addEventListener('touchstart', onPointerDown, { passive: true });
  window.addEventListener('touchend', onPointerUp, { passive: true });

  // Camera Presets API for UI Buttons
  window.setPraxis3DView = function (preset) {
    autoSpin = false;
    if (preset === 'front') {
      targetRotationX = 0.05;
      targetRotationY = 0;
    } else if (preset === 'iso') {
      targetRotationX = 0.22;
      targetRotationY = -0.45;
    } else if (preset === 'tilt') {
      targetRotationX = -0.15;
      targetRotationY = 0.5;
    } else if (preset === 'top') {
      targetRotationX = 0.65;
      targetRotationY = 0;
    }
  };

  window.togglePraxisAutoSpin = function () {
    autoSpin = !autoSpin;
    return autoSpin;
  };

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

    if (autoSpin && !isPointerDown) {
      targetRotationY = Math.sin(elapsed * 0.45) * 0.35;
      targetRotationX = 0.08 + Math.cos(elapsed * 0.3) * 0.06;
    }

    // Smooth lerp parallax for the master group
    masterGroup.rotation.y += (targetRotationY - masterGroup.rotation.y) * 0.06;
    masterGroup.rotation.x += (targetRotationX - masterGroup.rotation.x) * 0.06;

    // Subtle gentle floating bob for the whole laptop
    laptopGroup.position.y = -0.4 + Math.sin(elapsed * 1.2) * 0.08;

    // Periodic screen canvas refresh for blinking prompt
    if (Math.floor(elapsed * 60) % 15 === 0) {
      updateScreenCanvas();
      screenTexture.needsUpdate = true;
    }

    // AI Core Orb animations
    wireOrb.rotation.y = elapsed * 0.5;
    wireOrb.rotation.x = elapsed * 0.3;
    ringMesh1.rotation.z = elapsed * 0.8;
    ringMesh2.rotation.z = -elapsed * 0.6;
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
