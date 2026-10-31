/**
 * Praxis Linux (AIOS) — Live WebBrowser OS Desktop Simulator
 * Author: Mehul Khanna (MrMehulkhanna)
 * 100% Vanilla JavaScript & CSS3 Hardware-Accelerated Wayland/Quickshell Simulation.
 */

(function () {
  'use strict';

  document.addEventListener('DOMContentLoaded', initSimulator);

  function initSimulator() {
    const desktop = document.getElementById('sim-desktop');
    if (!desktop) return;

    // Elements
    const topClock = document.getElementById('sim-top-clock');
    const cpuMeter = document.getElementById('sim-cpu-val');
    const vramMeter = document.getElementById('sim-vram-val');
    const ramMeter = document.getElementById('sim-ram-val');
    const netMeter = document.getElementById('sim-net-val');
    const profilePill = document.getElementById('sim-profile-pill');
    const standbyPanel = document.getElementById('sim-standby-panel');
    const appDrawer = document.getElementById('sim-app-drawer');
    const fullscreenBtn = document.getElementById('sim-fullscreen-toggle');
    const simWrapper = document.getElementById('simulator-wrapper');

    // State
    let activeProfile = 'Normal';
    let activeWorkspace = 1;
    let highestZ = 10;
    let activeWallpaper = 'assets/wallpapers/deep-purple.png';
    let soundEnabled = true;

    // -----------------------------------------------------------------------
    // Tactile Web Audio API Synthesizer (Zero asset download required)
    // -----------------------------------------------------------------------
    let audioCtx = null;
    function getAudioContext() {
      if (!audioCtx) {
        const AudioContextClass = window.AudioContext || window.webkitAudioContext;
        if (AudioContextClass) {
          audioCtx = new AudioContextClass();
        }
      }
      if (audioCtx && audioCtx.state === 'suspended') {
        audioCtx.resume();
      }
      return audioCtx;
    }

    function playUiSound(type) {
      if (!soundEnabled) return;
      try {
        const ctx = getAudioContext();
        if (!ctx) return;
        const now = ctx.currentTime;

        if (type === 'click') {
          // Subtle, soft glass click (0.04s)
          const osc = ctx.createOscillator();
          const gain = ctx.createGain();
          osc.type = 'sine';
          osc.frequency.setValueAtTime(780, now);
          osc.frequency.exponentialRampToValueAtTime(320, now + 0.04);
          gain.gain.setValueAtTime(0.08, now);
          gain.gain.exponentialRampToValueAtTime(0.001, now + 0.04);
          osc.connect(gain);
          gain.connect(ctx.destination);
          osc.start(now);
          osc.stop(now + 0.04);
        } else if (type === 'type') {
          // Subtle mechanical key clack
          const osc = ctx.createOscillator();
          const gain = ctx.createGain();
          osc.type = 'triangle';
          osc.frequency.setValueAtTime(280 + Math.random() * 80, now);
          gain.gain.setValueAtTime(0.035, now);
          gain.gain.exponentialRampToValueAtTime(0.001, now + 0.025);
          osc.connect(gain);
          gain.connect(ctx.destination);
          osc.start(now);
          osc.stop(now + 0.025);
        } else if (type === 'focus') {
          // Smooth acoustic bubble
          const osc = ctx.createOscillator();
          const gain = ctx.createGain();
          osc.type = 'sine';
          osc.frequency.setValueAtTime(420, now);
          osc.frequency.exponentialRampToValueAtTime(560, now + 0.06);
          gain.gain.setValueAtTime(0.06, now);
          gain.gain.exponentialRampToValueAtTime(0.001, now + 0.06);
          osc.connect(gain);
          gain.connect(ctx.destination);
          osc.start(now);
          osc.stop(now + 0.06);
        } else if (type === 'chime') {
          // Dual harmonic bell chord
          [587.33, 880].forEach((freq) => {
            const osc = ctx.createOscillator();
            const gain = ctx.createGain();
            osc.type = 'sine';
            osc.frequency.setValueAtTime(freq, now);
            gain.gain.setValueAtTime(0.05, now);
            gain.gain.exponentialRampToValueAtTime(0.0005, now + 0.28);
            osc.connect(gain);
            gain.connect(ctx.destination);
            osc.start(now);
            osc.stop(now + 0.28);
          });
        } else if (type === 'close') {
          // Soft down-swoosh
          const osc = ctx.createOscillator();
          const gain = ctx.createGain();
          osc.type = 'sine';
          osc.frequency.setValueAtTime(320, now);
          osc.frequency.exponentialRampToValueAtTime(140, now + 0.07);
          gain.gain.setValueAtTime(0.05, now);
          gain.gain.exponentialRampToValueAtTime(0.001, now + 0.07);
          osc.connect(gain);
          gain.connect(ctx.destination);
          osc.start(now);
          osc.stop(now + 0.07);
        }
      } catch (err) {
        // Fail gracefully
      }
    }

    // Sound toggle button wiring
    const soundToggle = document.getElementById('sim-sound-toggle');
    if (soundToggle) {
      soundToggle.addEventListener('click', (e) => {
        e.stopPropagation();
        soundEnabled = !soundEnabled;
        if (soundEnabled) {
          soundToggle.textContent = '🔊 Sound ON';
          soundToggle.classList.remove('muted');
          playUiSound('chime');
          notifySim('Tactile UI Audio enabled.');
        } else {
          soundToggle.textContent = '🔇 Sound OFF';
          soundToggle.classList.add('muted');
          notifySim('Tactile UI Audio muted.');
        }
      });
    }

    // Welcome Card close
    const welcomeCard = document.getElementById('sim-welcome-card');
    const welcomeClose = document.getElementById('sim-welcome-close');
    if (welcomeClose && welcomeCard) {
      welcomeClose.addEventListener('click', () => {
        playUiSound('click');
        welcomeCard.classList.add('hidden');
      });
    }

    // -----------------------------------------------------------------------
    // 1. Live Clock & Dynamic Telemetry
    // -----------------------------------------------------------------------
    function updateClock() {
      const now = new Date();
      const timeStr = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false });
      const dateStr = now.toLocaleDateString([], { month: 'short', day: 'numeric' });
      if (topClock) topClock.textContent = `${dateStr}  ${timeStr}`;
    }
    updateClock();
    setInterval(updateClock, 1000);

    // Dynamic system load fluctuations
    setInterval(() => {
      if (!cpuMeter) return;
      const baseCpu = activeProfile === 'Game Mode' ? 42 : 14;
      const cpu = Math.min(99, Math.max(8, baseCpu + Math.floor((Math.random() - 0.45) * 8)));
      cpuMeter.textContent = `${cpu}%`;

      const vram = (2.2 + Math.random() * 0.3).toFixed(1);
      if (vramMeter) vramMeter.textContent = `${vram}/8.0 GB`;

      const ram = (4.1 + Math.random() * 0.2).toFixed(1);
      if (ramMeter) ramMeter.textContent = `${ram}/32 GB`;

      const netDown = (10 + Math.random() * 15).toFixed(1);
      if (netMeter) netMeter.textContent = `${netDown} MB/s`;
    }, 2400);

    // -----------------------------------------------------------------------
    // 2. Profile Switcher (Normal / Game Mode / Battery / AI Mode)
    // -----------------------------------------------------------------------
    const profileMenuItems = document.querySelectorAll('.sim-profile-option');
    if (profilePill) {
      profilePill.addEventListener('click', (e) => {
        e.stopPropagation();
        const menu = document.getElementById('sim-profile-dropdown');
        if (menu) menu.classList.toggle('active');
      });
    }

    profileMenuItems.forEach((item) => {
      item.addEventListener('click', () => {
        const prof = item.getAttribute('data-profile');
        setProfile(prof);
        const menu = document.getElementById('sim-profile-dropdown');
        if (menu) menu.classList.remove('active');
      });
    });

    document.addEventListener('click', () => {
      const menu = document.getElementById('sim-profile-dropdown');
      if (menu) menu.classList.remove('active');
    });

    function setProfile(name) {
      activeProfile = name;
      if (profilePill) profilePill.textContent = name;
      desktop.setAttribute('data-profile', name);

      if (name === 'Game Mode') {
        desktop.style.setProperty('--sim-blur', '0px');
        notifySim('Game Mode Active: Compositor blur bypassed, CPU governor set to performance, 120Hz unlocked.');
      } else if (name === 'Battery Saver') {
        desktop.style.setProperty('--sim-blur', '10px');
        desktop.style.backgroundImage = "url('assets/wallpapers/oled-black.jpg')";
        notifySim('Battery Saver Active: Display clamped to 60Hz, OLED pure black theme engaged.');
      } else if (name === 'AI Mode') {
        notifySim('AI Mode: Local LLM unloaded from VRAM. Full RTX 4060 GPU capacity released.');
      } else {
        desktop.style.setProperty('--sim-blur', '16px');
        desktop.style.backgroundImage = `url('${activeWallpaper}')`;
        notifySim('Profile switched to Normal (Adaptive Balanced).');
      }
    }

    // -----------------------------------------------------------------------
    // 3. Window Management (Drag, Z-Index, Minimize, Maximize, Close)
    // -----------------------------------------------------------------------
    const windows = document.querySelectorAll('.sim-window');

    windows.forEach((win) => {
      const titlebar = win.querySelector('.sim-win-titlebar');
      const closeBtn = win.querySelector('.sim-win-btn.close');
      const minBtn = win.querySelector('.sim-win-btn.min');
      const maxBtn = win.querySelector('.sim-win-btn.max');

      // Bring to front
      win.addEventListener('mousedown', () => bringToFront(win));
      win.addEventListener('touchstart', () => bringToFront(win), { passive: true });

      // Dragging logic with Windows 11 Snap Assist
      if (titlebar) {
        let isDragging = false;
        let startX, startY, startLeft, startTop;
        let currentSnap = null;
        const snapPreview = document.getElementById('sim-snap-preview');

        titlebar.addEventListener('mousedown', (e) => {
          if (e.target.closest('.sim-win-controls')) return;
          bringToFront(win);
          isDragging = true;
          startX = e.clientX;
          startY = e.clientY;
          const rect = win.getBoundingClientRect();
          const deskRect = desktop.getBoundingClientRect();
          startLeft = rect.left - deskRect.left;
          startTop = rect.top - deskRect.top;

          function onMouseMove(e) {
            if (!isDragging) return;
            const dx = e.clientX - startX;
            const dy = e.clientY - startY;
            const deskW = desktop.clientWidth;
            const deskH = desktop.clientHeight;
            const winW = win.clientWidth;
            const winH = win.clientHeight;

            let newLeft = Math.max(0, Math.min(deskW - winW, startLeft + dx));
            let newTop = Math.max(38, Math.min(deskH - winH - 60, startTop + dy));

            win.style.left = `${newLeft}px`;
            win.style.top = `${newTop}px`;
            win.style.right = 'auto';
            win.style.bottom = 'auto';
            win.style.transform = 'none';

            // Windows 11 Edge Snapping detection
            const mouseX = e.clientX - deskRect.left;
            const mouseY = e.clientY - deskRect.top;

            if (mouseY <= 42) {
              currentSnap = 'max';
              if (snapPreview) {
                snapPreview.style.top = '38px';
                snapPreview.style.left = '8px';
                snapPreview.style.width = `${deskW - 16}px`;
                snapPreview.style.height = `${deskH - 46}px`;
                snapPreview.classList.add('visible');
              }
            } else if (mouseX <= 24) {
              currentSnap = 'left';
              if (snapPreview) {
                snapPreview.style.top = '38px';
                snapPreview.style.left = '8px';
                snapPreview.style.width = `${(deskW / 2) - 12}px`;
                snapPreview.style.height = `${deskH - 46}px`;
                snapPreview.classList.add('visible');
              }
            } else if (mouseX >= deskW - 24) {
              currentSnap = 'right';
              if (snapPreview) {
                snapPreview.style.top = '38px';
                snapPreview.style.left = `${(deskW / 2) + 4}px`;
                snapPreview.style.width = `${(deskW / 2) - 12}px`;
                snapPreview.style.height = `${deskH - 46}px`;
                snapPreview.classList.add('visible');
              }
            } else {
              currentSnap = null;
              if (snapPreview) snapPreview.classList.remove('visible');
            }
          }

          function onMouseUp() {
            isDragging = false;
            window.removeEventListener('mousemove', onMouseMove);
            window.removeEventListener('mouseup', onMouseUp);

            if (snapPreview) snapPreview.classList.remove('visible');

            if (currentSnap === 'max') {
              win.classList.add('maximized');
              win.style.left = '';
              win.style.top = '';
              win.style.width = '';
              win.style.height = '';
              playUiSound('click');
              showSimToast('🗖 Window Maximized (Windows Snap)');
            } else if (currentSnap === 'left') {
              win.classList.remove('maximized');
              win.style.left = '8px';
              win.style.top = '38px';
              win.style.width = `${(desktop.clientWidth / 2) - 12}px`;
              win.style.height = `${desktop.clientHeight - 46}px`;
              playUiSound('click');
              showSimToast('🗗 Snapped to Left Half (Win+←)');
            } else if (currentSnap === 'right') {
              win.classList.remove('maximized');
              win.style.left = `${(desktop.clientWidth / 2) + 4}px`;
              win.style.top = '38px';
              win.style.width = `${(desktop.clientWidth / 2) - 12}px`;
              win.style.height = `${desktop.clientHeight - 46}px`;
              playUiSound('click');
              showSimToast('🗗 Snapped to Right Half (Win+→)');
            }
            currentSnap = null;
          }

          window.addEventListener('mousemove', onMouseMove);
          window.addEventListener('mouseup', onMouseUp);
        });
      }

      // Close
      if (closeBtn) {
        closeBtn.addEventListener('click', () => {
          playUiSound('close');
          win.classList.add('closed');
          win.classList.remove('active');
          updateDockIndicators();
        });
      }

      // Minimize
      if (minBtn) {
        minBtn.addEventListener('click', () => {
          playUiSound('close');
          win.classList.add('minimized');
          win.classList.remove('active');
          updateDockIndicators();
        });
      }

      // Maximize / Restore
      if (maxBtn) {
        maxBtn.addEventListener('click', () => {
          playUiSound('click');
          win.classList.toggle('maximized');
          bringToFront(win);
        });
      }
    });

    function bringToFront(win) {
      highestZ += 2;
      win.style.zIndex = highestZ;
      windows.forEach((w) => w.classList.remove('active'));
      win.classList.add('active');
      win.classList.remove('minimized');
      win.classList.remove('closed');

      playUiSound('focus');

      // Update Topbar Active Title
      const titleSpan = win.querySelector('.sim-win-title');
      const activeAppTag = document.getElementById('sim-active-app-title');
      if (titleSpan && activeAppTag) {
        activeAppTag.textContent = titleSpan.textContent;
      }
      updateDockIndicators();
    }

    // -----------------------------------------------------------------------
    // 4. Interactive Dock & Launcher
    // -----------------------------------------------------------------------
    const dockItems = document.querySelectorAll('.sim-dock-icon');

    dockItems.forEach((icon) => {
      icon.addEventListener('click', () => {
        const appName = icon.getAttribute('data-app');
        toggleAppWindow(appName);
      });
    });

    function toggleAppWindow(appName) {
      const targetWin = document.getElementById(`sim-win-${appName}`);
      if (!targetWin) return;

      playUiSound('click');

      if (targetWin.classList.contains('closed') || targetWin.classList.contains('minimized')) {
        targetWin.classList.remove('closed');
        targetWin.classList.remove('minimized');
        bringToFront(targetWin);
      } else if (targetWin.classList.contains('active')) {
        targetWin.classList.add('minimized');
        targetWin.classList.remove('active');
        playUiSound('close');
      } else {
        bringToFront(targetWin);
      }
      updateDockIndicators();
    }
    window.toggleAppWindow = toggleAppWindow;

    function updateDockIndicators() {
      dockItems.forEach((icon) => {
        const app = icon.getAttribute('data-app');
        const win = document.getElementById(`sim-win-${app}`);
        if (win && !win.classList.contains('closed')) {
          icon.classList.add('running');
          if (win.classList.contains('active')) {
            icon.classList.add('focused');
          } else {
            icon.classList.remove('focused');
          }
        } else {
          icon.classList.remove('running', 'focused');
        }
      });
    }

    // -----------------------------------------------------------------------
    // 4B. Auto-Dock & Windows 11 Show Desktop & Snapping
    // -----------------------------------------------------------------------
    const dockEl = document.getElementById('sim-dock');
    const dockRevealZone = document.getElementById('sim-dock-reveal-zone');
    const dockToggleBtn = document.getElementById('sim-dock-toggle-btn');
    const showDesktopBtn = document.getElementById('sim-show-desktop-btn');
    let autoDockEnabled = true;
    let dockHideTimer = null;

    function revealDock() {
      if (dockHideTimer) clearTimeout(dockHideTimer);
      if (dockEl) dockEl.classList.remove('dock-hidden');
    }

    function scheduleDockHide() {
      if (!autoDockEnabled) return;
      if (dockHideTimer) clearTimeout(dockHideTimer);
      dockHideTimer = setTimeout(() => {
        if (dockEl && autoDockEnabled && !dockEl.matches(':hover')) {
          dockEl.classList.add('dock-hidden');
        }
      }, 450);
    }

    if (dockEl) {
      dockEl.addEventListener('mouseenter', revealDock);
      dockEl.addEventListener('mouseleave', () => {
        if (autoDockEnabled) scheduleDockHide();
      });
    }

    if (dockRevealZone) {
      dockRevealZone.addEventListener('mouseenter', revealDock);
      dockRevealZone.addEventListener('mousemove', revealDock);
    }

    desktop.addEventListener('mousemove', (e) => {
      if (!autoDockEnabled) return;
      const deskRect = desktop.getBoundingClientRect();
      const mouseYFromBottom = deskRect.bottom - e.clientY;
      if (mouseYFromBottom <= 35) {
        revealDock();
      } else {
        if (dockEl && !dockEl.matches(':hover')) {
          scheduleDockHide();
        }
      }
    });

    if (dockToggleBtn) {
      dockToggleBtn.addEventListener('click', () => {
        autoDockEnabled = !autoDockEnabled;
        if (autoDockEnabled) {
          dockToggleBtn.classList.remove('off');
          dockToggleBtn.textContent = '⚡ Auto-Dock: ON';
          showSimToast('⚡ Auto-Dock Enabled (hides when mouse moves away)');
          scheduleDockHide();
        } else {
          dockToggleBtn.classList.add('off');
          dockToggleBtn.textContent = '⚡ Auto-Dock: OFF';
          revealDock();
          showSimToast('⚡ Auto-Dock Disabled (dock stays visible)');
        }
        playUiSound('click');
      });
    }

    // Windows 11 Show Desktop (Win+D)
    let lastMinimizedByShowDesktop = [];
    function toggleShowDesktop() {
      const visibleWins = Array.from(windows).filter(w => !w.classList.contains('closed') && !w.classList.contains('minimized'));
      if (visibleWins.length > 0) {
        lastMinimizedByShowDesktop = visibleWins;
        visibleWins.forEach(w => {
          w.classList.add('minimized');
          w.classList.remove('active');
        });
        playUiSound('close');
        showSimToast('🖥️ Show Desktop (Win+D)');
      } else if (lastMinimizedByShowDesktop.length > 0) {
        lastMinimizedByShowDesktop.forEach(w => {
          w.classList.remove('minimized');
        });
        if (lastMinimizedByShowDesktop[0]) bringToFront(lastMinimizedByShowDesktop[0]);
        lastMinimizedByShowDesktop = [];
        playUiSound('click');
        showSimToast('🖥️ Windows Restored');
      }
      updateDockIndicators();
    }
    window.toggleShowDesktop = toggleShowDesktop;

    if (showDesktopBtn) {
      showDesktopBtn.addEventListener('click', toggleShowDesktop);
    }

    // Windows 11 Snapping via keyboard shortcuts (Win+Arrows)
    function snapActiveWindow(action) {
      const activeWin = Array.from(windows).find(w => w.classList.contains('active') && !w.classList.contains('closed') && !w.classList.contains('minimized'));
      if (!activeWin) return;
      const deskW = desktop.clientWidth;
      const deskH = desktop.clientHeight;

      if (action === 'max') {
        activeWin.classList.toggle('maximized');
        activeWin.style.left = '';
        activeWin.style.top = '';
        activeWin.style.width = '';
        activeWin.style.height = '';
        playUiSound('click');
        showSimToast(activeWin.classList.contains('maximized') ? '🗖 Window Maximized (Win+↑)' : 'Window Restored');
      } else if (action === 'left') {
        activeWin.classList.remove('maximized');
        activeWin.style.left = '8px';
        activeWin.style.top = '38px';
        activeWin.style.width = `${(deskW / 2) - 12}px`;
        activeWin.style.height = `${deskH - 46}px`;
        playUiSound('click');
        showSimToast('🗗 Snapped to Left Half (Win+←)');
      } else if (action === 'right') {
        activeWin.classList.remove('maximized');
        activeWin.style.left = `${(deskW / 2) + 4}px`;
        activeWin.style.top = '38px';
        activeWin.style.width = `${(deskW / 2) - 12}px`;
        activeWin.style.height = `${deskH - 46}px`;
        playUiSound('click');
        showSimToast('🗗 Snapped to Right Half (Win+→)');
      } else if (action === 'restore') {
        if (activeWin.classList.contains('maximized')) {
          activeWin.classList.remove('maximized');
        } else {
          activeWin.classList.add('minimized');
          activeWin.classList.remove('active');
        }
        playUiSound('close');
        updateDockIndicators();
      }
    }
    window.snapActiveWindow = snapActiveWindow;

    // App Drawer Toggle
    const appDrawerBtn = document.getElementById('sim-app-drawer-toggle');
    if (appDrawerBtn && appDrawer) {
      appDrawerBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        playUiSound('click');
        appDrawer.classList.toggle('open');
      });
    }

    // App Drawer Search & Item Click
    const drawerSearch = document.getElementById('sim-drawer-input');
    const drawerItems = document.querySelectorAll('.sim-drawer-item');

    if (drawerSearch) {
      drawerSearch.addEventListener('input', (e) => {
        const query = e.target.value.toLowerCase().trim();
        drawerItems.forEach((item) => {
          const name = item.querySelector('.sim-drawer-name')?.textContent.toLowerCase() || '';
          const sub = item.querySelector('.sim-drawer-sub')?.textContent.toLowerCase() || '';
          if (!query || name.includes(query) || sub.includes(query)) {
            item.style.display = 'flex';
          } else {
            item.style.display = 'none';
          }
        });
      });
    }

    drawerItems.forEach((item) => {
      item.addEventListener('click', () => {
        const app = item.getAttribute('data-open');
        if (app) {
          toggleAppWindow(app);
          if (appDrawer) appDrawer.classList.remove('open');
        }
      });
    });

    // Close app drawer on click outside
    document.addEventListener('click', (e) => {
      if (appDrawer && !appDrawer.contains(e.target) && e.target !== appDrawerBtn) {
        appDrawer.classList.remove('open');
      }
    });

    // StandBy Widget Board Toggle (Super+B)
    const standbyBtn = document.getElementById('sim-standby-toggle');
    if (standbyBtn && standbyPanel) {
      standbyBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        playUiSound('click');
        standbyPanel.classList.toggle('open');
      });
    }

    // Workspaces
    const wsBtns = document.querySelectorAll('.sim-ws-btn');
    wsBtns.forEach((btn) => {
      btn.addEventListener('click', () => {
        playUiSound('chime');
        wsBtns.forEach((b) => b.classList.remove('active'));
        btn.classList.add('active');
        activeWorkspace = parseInt(btn.getAttribute('data-ws'), 10);
        notifySim(`Switched to Workspace ${activeWorkspace}`);
      });
    });

    // -----------------------------------------------------------------------
    // File Manager (Thunar) Logic
    // -----------------------------------------------------------------------
    const fileItemsMap = {
      home: [
        { name: 'Desktop', icon: '📁', meta: 'Directory • 3 items' },
        { name: 'Documents', icon: '📁', meta: 'Directory • 6 items' },
        { name: 'Wallpapers', icon: '🖼️', meta: 'Directory • 12 items' },
        { name: 'Projects', icon: '⚡', meta: 'Directory • 14 repos' },
        { name: '.bashrc', icon: '📄', meta: '3.2 KB • Shell' },
        { name: '.zshrc', icon: '📄', meta: '4.8 KB • Shell' }
      ],
      wallpapers: [
        { name: 'deep-purple.png', icon: '🖼️', meta: '4.2 MB • Wallpaper', wp: 'assets/wallpapers/deep-purple.png', title: 'Deep Purple' },
        { name: 'cosmic-nebula.jpg', icon: '🖼️', meta: '5.1 MB • Wallpaper', wp: 'assets/wallpapers/cosmic-nebula.jpg', title: 'Cosmic Nebula' },
        { name: 'electric-aurora.jpg', icon: '🖼️', meta: '3.8 MB • Wallpaper', wp: 'assets/wallpapers/electric-aurora.jpg', title: 'Electric Aurora' },
        { name: 'cyber-matrix.jpg', icon: '🖼️', meta: '4.7 MB • Wallpaper', wp: 'assets/wallpapers/cyber-matrix.jpg', title: 'Cyber Matrix' },
        { name: 'midnight-waves.jpg', icon: '🖼️', meta: '4.0 MB • Wallpaper', wp: 'assets/wallpapers/midnight-waves.jpg', title: 'Midnight Waves' },
        { name: 'abyssal-violet.jpg', icon: '🖼️', meta: '3.9 MB • Wallpaper', wp: 'assets/wallpapers/abyssal-violet.jpg', title: 'Abyssal Violet' },
        { name: 'prism-glass.jpg', icon: '🖼️', meta: '4.4 MB • Wallpaper', wp: 'assets/wallpapers/prism-glass.jpg', title: 'Prism Glass' },
        { name: 'oled-black.jpg', icon: '🖼️', meta: '1.2 MB • Wallpaper', wp: 'assets/wallpapers/oled-black.jpg', title: 'OLED Black' }
      ],
      projects: [
        { name: 'aios-daemon.py', icon: '🐍', meta: '14.2 KB • Python' },
        { name: 'hyprland.conf', icon: '⚙️', meta: '8.4 KB • Wayland Config' },
        { name: 'Theme.qml', icon: '🎨', meta: '2.1 KB • Quickshell QML' },
        { name: 'audio-guard.py', icon: '🔊', meta: '5.6 KB • PipeWire Daemon' },
        { name: 'build-iso.sh', icon: '📦', meta: '4.9 KB • Archiso Script' },
        { name: 'test-runner.sh', icon: '🧪', meta: '3.1 KB • Gravitas Spec' }
      ],
      docs: [
        { name: 'README.md', icon: '📄', meta: '5.9 KB • Distro Overview' },
        { name: 'ARCHITECTURE.md', icon: '📐', meta: '12.4 KB • Spec Doc' },
        { name: 'ISO_BUILD_GUIDE.md', icon: '💿', meta: '7.8 KB • Build Manual' },
        { name: 'WAYLAND_SPECS.md', icon: '⚡', meta: '9.1 KB • Compositor Guide' }
      ],
      system: [
        { name: '/boot', icon: '📁', meta: 'Kernel 6.11.5-bore' },
        { name: '/etc/hypr', icon: '📁', meta: 'Compositor configs' },
        { name: '/usr/share/quickshell', icon: '📁', meta: 'QML Glass Engine' },
        { name: '/var/log/aios', icon: '📁', meta: 'Local SQLite Audit Log' }
      ],
      iso: [
        { name: 'praxis-2026-x86_64.iso', icon: '💿', meta: '2.4 GB • Bootable Hybrid ISO' },
        { name: 'sha256sums.txt', icon: '🔒', meta: '128 B • Cryptographic Hash' },
        { name: 'grub.cfg', icon: '⚙️', meta: '1.4 KB • EFI GRUB Bootloader' }
      ]
    };

    const sidebarItems = document.querySelectorAll('.sim-sidebar-item');
    const filesGrid = document.getElementById('sim-files-grid');
    const folderLabel = document.getElementById('sim-current-folder');
    const fileCountLabel = document.getElementById('sim-files-count');

    sidebarItems.forEach((item) => {
      item.addEventListener('click', () => {
        playUiSound('click');
        const folder = item.getAttribute('data-folder');
        sidebarItems.forEach((i) => i.classList.remove('active'));
        item.classList.add('active');
        renderFolder(folder);
      });
    });

    function renderFolder(folder) {
      if (folderLabel) folderLabel.textContent = folder;
      const list = fileItemsMap[folder] || [];
      if (fileCountLabel) fileCountLabel.textContent = `${list.length} items`;
      if (!filesGrid) return;

      filesGrid.innerHTML = '';
      list.forEach((f) => {
        const div = document.createElement('div');
        div.className = 'sim-file-item';
        div.innerHTML = `
          <span class="sim-file-icon">${f.icon}</span>
          <span class="sim-file-name">${escapeHtml(f.name)}</span>
          <span class="sim-file-meta">${escapeHtml(f.meta)}</span>
        `;
        div.addEventListener('click', () => {
          playUiSound('click');
          if (f.wp) {
            window.previewWallpaperInSimulator(f.wp, f.title);
          } else {
            window.simOpenFile(f.name);
          }
        });
        filesGrid.appendChild(div);
      });
    }

    window.simOpenFile = function (fileName) {
      playUiSound('click');
      notifySim(`Inspecting: ${fileName}`);
      if (fileName.endsWith('.conf') || fileName.endsWith('.qml') || fileName.endsWith('.py') || fileName.endsWith('.md')) {
        toggleAppWindow('code');
      } else if (fileName.endsWith('.iso')) {
        toggleAppWindow('browser');
        window.loadBrowserPage('iso');
      }
    };

    // -----------------------------------------------------------------------
    // Web Browser (Chromium) Logic
    // -----------------------------------------------------------------------
    const browserPages = {
      docs: {
        url: 'https://praxis-os.org/docs',
        html: `
          <div class="sim-browser-page">
            <div class="sim-b-hero">
              <div class="sim-b-tag">OFFLINE-FIRST HYBRID LINUX DISTRO</div>
              <h3>Praxis Linux Knowledge Base</h3>
              <p>Welcome to the built-in offline documentation running locally inside Praxis OS. Explore architecture guides, AI pipeline specs, and Wayland compositor tuning.</p>
            </div>
            <div class="sim-b-grid">
              <div class="sim-b-card">
                <h4>Local AI Intelligence</h4>
                <p>32-layer GGUF quantization offloaded directly onto RTX 4060 VRAM. Never sends your keystrokes or audio to the cloud.</p>
              </div>
              <div class="sim-b-card">
                <h4>Hyprland 120Hz Springs</h4>
                <p>Fluid physics gestures, dynamic dual-monitor hotplugging, and zero-tearing direct scanout Wayland compositor.</p>
              </div>
              <div class="sim-b-card">
                <h4>Audio &amp; Bluetooth Guard</h4>
                <p>Automated BlueZ D-Bus agent pairing, instant PipeWire profile switching, and zero crackle low-latency audio.</p>
              </div>
            </div>
          </div>
        `
      },
      github: {
        url: 'https://github.com/MrMehulkhanna/praxis',
        html: `
          <div class="sim-browser-page">
            <div class="sim-b-hero">
              <div class="sim-b-tag">OPEN SOURCE REPOSITORY</div>
              <h3>MrMehulkhanna / praxis</h3>
              <p>Next-generation Linux distribution blending local AI copiloting, Quickshell hardware-accelerated frosted glass, and automated hardware management.</p>
            </div>
            <div class="sim-b-grid">
              <div class="sim-b-card">
                <h4>Active Branch</h4>
                <p><code style="color: #7dcfff;">main</code> • Continuous deployment enabled via GitHub Pages.</p>
              </div>
              <div class="sim-b-card">
                <h4>Zero External CDNs</h4>
                <p>100% self-contained assets, offline fonts, and local vector icons for strict privacy.</p>
              </div>
            </div>
          </div>
        `
      },
      ai: {
        url: 'http://localhost:8080/v1/models',
        html: `
          <div class="sim-browser-page">
            <div class="sim-b-hero">
              <div class="sim-b-tag">LOCAL TOKEN ENGINE</div>
              <h3>llama.cpp CUDA Inference Gateway</h3>
              <p>High-throughput local LLM server listening on loopback interface with hardware offloading.</p>
            </div>
            <div class="sim-b-grid">
              <div class="sim-b-card">
                <h4>Model Architecture</h4>
                <p>Qwen-2.5-Coder-7B-Instruct (4-bit quantization, 32 GPU layers offloaded).</p>
              </div>
              <div class="sim-b-card">
                <h4>Throughput &amp; Latency</h4>
                <p>46.2 tokens/sec prompt evaluation • 12ms time-to-first-token • Zero internet required.</p>
              </div>
            </div>
          </div>
        `
      },
      iso: {
        url: 'https://praxis-os.org/download',
        html: `
          <div class="sim-browser-page">
            <div class="sim-b-hero">
              <div class="sim-b-tag">PRODUCTION RELEASE</div>
              <h3>Praxis Linux v2026 Bootable Image</h3>
              <p>Download the official hybrid ISO with CachyOS BORE kernel, NVIDIA CUDA drivers, and Quickshell desktop pre-installed.</p>
            </div>
            <div class="sim-b-grid">
              <div class="sim-b-card">
                <h4>Size &amp; Compatibility</h4>
                <p>2.4 GB • UEFI &amp; Legacy BIOS • Ventoy / Rufus / dd compatible bootloader.</p>
              </div>
              <div class="sim-b-card">
                <h4>Recommended Hardware</h4>
                <p>Intel/AMD x86_64 CPU • 8GB+ RAM • NVIDIA RTX or AMD Radeon GPU for full AI acceleration.</p>
              </div>
            </div>
          </div>
        `
      }
    };

    window.loadBrowserPage = function (pageKey) {
      playUiSound('click');
      const page = browserPages[pageKey];
      if (!page) return;
      const urlInput = document.getElementById('sim-browser-url');
      const content = document.getElementById('sim-browser-content');
      if (urlInput) urlInput.value = page.url;
      if (content) content.innerHTML = page.html;
    };

    // -----------------------------------------------------------------------
    // 5. Interactive Terminal Shell in Simulator
    // -----------------------------------------------------------------------
    const termInput = document.getElementById('sim-term-input');
    const termOutput = document.getElementById('sim-term-log');
    const quickCmdBtns = document.querySelectorAll('.sim-quick-cmd');

    const terminalResponses = {
      help: `Available Praxis OS commands:
  • neofetch         — Show system hardware, Wayland compositor, and theme
  • aios status      — Check local LLM daemon, Whisper speech, and sandbox
  • aios chat <msg>  — Query local context engine with zero cloud leakage
  • sensors          — Read CPU / RTX 4060 GPU thermals and fan curves
  • bt-scan          — Run automated BlueZ D-Bus PIN pairing agent
  • wifi-scan        — Multi-band 30s background Wi-Fi scanner
  • clear            — Reset terminal screen`,

      neofetch: `
  <span style="color: #bb9af7;">       /\\       </span>   <span style="color: #7dcfff; font-weight: bold;">mk@praxis-omen16</span>
  <span style="color: #bb9af7;">      /  \\      </span>   -----------------
  <span style="color: #bb9af7;">     / /\\ \\     </span>   <span style="color: #7aa2f7;">OS:</span> Praxis Linux x86_64 (AIOS v2026)
  <span style="color: #bb9af7;">    / /__\\ \\    </span>   <span style="color: #7aa2f7;">Host:</span> HP Omen Gaming Laptop 16-wd0xxx
  <span style="color: #bb9af7;">   / /____\\ \\   </span>   <span style="color: #7aa2f7;">Kernel:</span> 6.11.5-cachyos-bore
  <span style="color: #7dcfff;">  /_/      \\_\\  </span>   <span style="color: #7aa2f7;">Uptime:</span> 14 days, 3 hours
                   <span style="color: #7aa2f7;">Packages:</span> 1240 (pacman)
                   <span style="color: #7aa2f7;">Shell:</span> zsh 5.9
                   <span style="color: #7aa2f7;">Compositor:</span> Hyprland 0.44.1 (120Hz Springs)
                   <span style="color: #7aa2f7;">Desktop:</span> Quickshell QML Frosted Glass
                   <span style="color: #7aa2f7;">Theme:</span> Tokyo Obsidian [GTK3/4]
                   <span style="color: #7aa2f7;">Icons:</span> Papirus-Dark
                   <span style="color: #7aa2f7;">CPU:</span> 14th Gen Intel Core i7-14700HX (20) @ 5.00GHz
                   <span style="color: #7aa2f7;">GPU:</span> NVIDIA GeForce RTX 4060 Mobile (8GB VRAM)
                   <span style="color: #7aa2f7;">Memory:</span> 4.12 GiB / 31.82 GiB (ZRAM zstd: 0% thrash)
                   <span style="color: #7aa2f7;">AI Engine:</span> aios.service (llama.cpp CUDA + Whisper)`,

      'aios status': `[aios.service] System Daemon Status:
  ● Service: active (running) since boot
  ● Local Model: Qwen-2.5-Coder-7B-Q4_K_M (CUDA Offload: 32/32 layers)
  ● Inference Speed: 46.2 tokens/sec (RTX 4060 GPU)
  ● Whisper Daemon: Ready (Super+H push-to-talk microphone buffer)
  ● Privacy Gateway: DEFAULT-DENY (Zero outbound network telemetry)
  ● Audit Log: SQLite FTS5 store (/var/log/aios/audit.db)`,

      sensors: `[praxis-hwmon] Hardware Sensor Telemetry:
  ● CPU Package: 44.0°C (Core Max: 48°C)
  ● RTX 4060 GPU: 41.2°C (VRAM: 45°C, Hotspot: 47°C)
  ● Battery State: Discharging (98%, 4h 12m remaining @ 14.2W)
  ● Fan 1 (CPU): 1320 RPM (Silent Profile)
  ● Fan 2 (GPU): 0 RPM (Passive Idle Curve)`,

      'bt-scan': `[praxis-bt] Automated BlueZ D-Bus Agent scanning (30s cycle)...
  [DISCOVERY] Device: "Bluetooth Wireless Keyboard"
  [AGENT] BlueZ Agent handling automated PIN/passkey pairing handshake
  [SUCCESS] Device paired, trusted, and mapped to Wayland input seat0.
  Latency: 4.8ms | Battery: 94%`,

      'wifi-scan': `[praxis-net] NetworkManager Multi-Band Wi-Fi Scan (2.4GHz + 5GHz + 6GHz):
  ✔ "Praxis-Lab-5G"     | Ch 44  | -42 dBm | WPA3-SAE | 1200 Mbps (Connected)
  ✔ "Home-Fiber-6E"     | Ch 149 | -64 dBm | WPA3-SAE | 866 Mbps
  ✔ "Office-Guest"      | Ch 6   | -78 dBm | WPA2-PSK | 144 Mbps
  Active Interface: wlan0 (Intel Wi-Fi 6E AX211) — Zero scan freeze.`,

      clear: 'CLEAR_SCREEN'
    };

    function executeCommand(rawCmd) {
      const cmd = rawCmd.trim();
      if (!cmd) return;

      // Append user command
      const cmdRow = document.createElement('div');
      cmdRow.className = 'term-line user';
      cmdRow.innerHTML = `<span class="term-prompt">mk@praxis:~$</span> <span class="term-cmd">${escapeHtml(cmd)}</span>`;
      termOutput.appendChild(cmdRow);

      let reply = '';
      if (cmd.startsWith('aios chat ') || cmd.startsWith('ai ')) {
        const query = cmd.replace(/^(aios chat |ai )/, '');
        reply = `[aios-agent] Local Query: "${escapeHtml(query)}"
Analyzing kernel sysfs and local project context...
✔ Diagnostic: System health is optimal. Pressure Stall Index (PSI) is 0.00%.
  Your hardware is operating comfortably within thermal limits with zero background bloat.`;
      } else if (terminalResponses[cmd.toLowerCase()]) {
        reply = terminalResponses[cmd.toLowerCase()];
      } else {
        reply = `zsh: command not found: ${escapeHtml(cmd)}. Type 'help' for available Praxis commands.`;
      }

      if (reply === 'CLEAR_SCREEN') {
        termOutput.innerHTML = '';
      } else {
        const respRow = document.createElement('div');
        respRow.className = 'term-line output';
        respRow.innerHTML = `<pre class="term-pre">${reply}</pre>`;
        termOutput.appendChild(respRow);
      }

      termOutput.scrollTop = termOutput.scrollHeight;
    }

    if (termInput) {
      termInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
          playUiSound('click');
          executeCommand(termInput.value);
          termInput.value = '';
        } else if (e.key !== 'Shift' && e.key !== 'Control' && e.key !== 'Alt' && e.key !== 'Meta') {
          playUiSound('type');
        }
      });
    }

    quickCmdBtns.forEach((btn) => {
      btn.addEventListener('click', () => {
        playUiSound('click');
        const cmd = btn.getAttribute('data-cmd');
        executeCommand(cmd);
      });
    });

    // -----------------------------------------------------------------------
    // 6. Interactive Live Wallpaper Switcher
    // -----------------------------------------------------------------------
    const wallpaperCards = document.querySelectorAll('.sim-wp-thumb');

    wallpaperCards.forEach((thumb) => {
      thumb.addEventListener('click', () => {
        const wpSrc = thumb.getAttribute('data-wp');
        const wpTitle = thumb.getAttribute('data-title');
        setDesktopWallpaper(wpSrc, wpTitle);

        wallpaperCards.forEach((c) => c.classList.remove('active'));
        thumb.classList.add('active');
      });
    });

    function setDesktopWallpaper(src, title) {
      activeWallpaper = src;
      desktop.style.backgroundImage = `url('${src}')`;
      playUiSound('chime');
      notifySim(`Wallpaper changed to: ${title || src}`);
    }

    // Global hook for outside wallpaper gallery
    window.previewWallpaperInSimulator = function (src, title) {
      setDesktopWallpaper(src, title);
      const simSection = document.getElementById('simulator');
      if (simSection) {
        simSection.scrollIntoView({ behavior: 'smooth' });
      }
      // Open and bring wallpaper window to front
      const wpWin = document.getElementById('sim-win-wallpapers');
      if (wpWin) {
        wpWin.classList.remove('closed', 'minimized');
        bringToFront(wpWin);
      }
    };

    // -----------------------------------------------------------------------
    // 7. Glass Tuner & Control Sliders
    // -----------------------------------------------------------------------
    const alphaSlider = document.getElementById('slider-glass-alpha');
    const radiusSlider = document.getElementById('slider-radius');
    const blurToggle = document.getElementById('toggle-blur');

    if (alphaSlider) {
      alphaSlider.addEventListener('input', (e) => {
        const val = e.target.value;
        desktop.style.setProperty('--sim-glass-alpha', val);
        const label = document.getElementById('val-glass-alpha');
        if (label) label.textContent = `${Math.round(val * 100)}%`;
      });
    }

    if (radiusSlider) {
      radiusSlider.addEventListener('input', (e) => {
        const val = e.target.value;
        desktop.style.setProperty('--sim-radius', `${val}px`);
        const label = document.getElementById('val-radius');
        if (label) label.textContent = `${val}px`;
      });
    }

    if (blurToggle) {
      blurToggle.addEventListener('change', (e) => {
        desktop.style.setProperty('--sim-blur', e.target.checked ? '16px' : '0px');
      });
    }

    // Double-click titlebar to maximize / restore
    windows.forEach((win) => {
      const titlebar = win.querySelector('.sim-win-titlebar');
      if (titlebar) {
        titlebar.addEventListener('dblclick', () => {
          playUiSound('click');
          win.classList.toggle('maximized');
          bringToFront(win);
        });
      }
    });

    // -----------------------------------------------------------------------
    // 8. GUI AI Copilot Logic (Offline llama.cpp Simulation)
    // -----------------------------------------------------------------------
    const aiChatLog = document.getElementById('sim-ai-chat-log');
    const aiInput = document.getElementById('sim-ai-input');
    const aiSendBtn = document.getElementById('sim-ai-send-btn');
    const aiMicBtn = document.getElementById('sim-ai-mic-btn');

    const aiKnowledge = {
      zram: `**ZRAM Memory Guard Architecture:**\nUnlike Windows 11 which swaps cold pages to a high-latency disk paging file (causing 3–15 second UI freezes and high disk queue length), Praxis Linux compresses memory pages in RAM using **zstd compression** at over 4.2 GB/sec.\n- **Pressure Stall Index (PSI):** Monitored every 100ms.\n- **Thrashing:** 0.00% swap thrash even with 100 browser tabs open.\n- **Result:** Constant 120Hz compositor refresh with zero stutter.`,

      bluetooth: `**Automated BlueZ D-Bus Agent:**\nIn Praxis Linux, Bluetooth discovery bypasses the clunky Windows/GNOME PIN confirmation dropdown.\n- **Auto-Pair Handshake:** Matches standard HID keyboard vendor profiles and automatically processes passkey/PIN prompts through BlueZ D-Bus.\n- **Seat Mapping:** Automatically connects to Wayland input seat0 with ultra-low 4.8ms polling latency.`,

      dualboot: `**Safe Dual-Boot Alongside Windows:**\nPraxis Linux is designed specifically for everyday laptop users who still need Windows for specific games or software.\n- **Non-Destructive:** Uses \`ntfsresize\` to carve out an unallocated slice (80GB recommended) without touching your Windows partition table.\n- **BitLocker Safe:** Leaves your Windows BitLocker TPM PCR registers intact.\n- **UEFI Dual-Boot:** Configures systemd-boot to detect \`bootmgfw.efi\` so you can switch between Windows 11 and Praxis Linux seamlessly with 1 key.`,

      sensors: `**Hardware Sensor Diagnostics:**\n- **CPU:** Intel Core i7-14700HX @ 44.0°C (Fan: 1320 RPM - Silent Profile)\n- **GPU:** NVIDIA GeForce RTX 4060 Mobile @ 41.2°C (Fan: 0 RPM - Passive Idle)\n- **VRAM Offload:** 32/32 layers of Qwen-2.5-Coder allocated in dedicated VRAM.\n- **Battery:** 98% (Discharging @ 14.2W, 4h 12m remaining).`
    };

    window.askAiPrompt = function (query) {
      if (!query || !query.trim()) return;
      playUiSound('click');
      const cleanQ = query.trim();

      const aiWin = document.getElementById('sim-win-ai');
      if (aiWin && (aiWin.classList.contains('closed') || aiWin.classList.contains('minimized'))) {
        toggleAppWindow('ai');
      }

      const userMsg = document.createElement('div');
      userMsg.className = 'ai-chat-msg user';
      userMsg.innerHTML = `
        <div class="ai-avatar">👤</div>
        <div class="ai-bubble">${escapeHtml(cleanQ)}</div>
      `;
      if (aiChatLog) aiChatLog.appendChild(userMsg);

      let answer = '';
      const lower = cleanQ.toLowerCase();
      if (lower.includes('zram') || lower.includes('freeze') || lower.includes('memory') || lower.includes('ram')) {
        answer = aiKnowledge.zram;
      } else if (lower.includes('bluetooth') || lower.includes('keyboard') || lower.includes('pair')) {
        answer = aiKnowledge.bluetooth;
      } else if (lower.includes('dual') || lower.includes('windows') || lower.includes('install') || lower.includes('boot')) {
        answer = aiKnowledge.dualboot;
      } else if (lower.includes('sensor') || lower.includes('thermal') || lower.includes('temp') || lower.includes('fan') || lower.includes('cpu') || lower.includes('gpu')) {
        answer = aiKnowledge.sensors;
      } else {
        answer = `**Praxis Local Assistant:**\nI evaluated your query: "${cleanQ}" locally using Qwen-2.5-Coder-7B.\n- Kernel: 6.11.5-cachyos-bore with BORE (Burst-Oriented Response Enhancer) scheduling.\n- System Load: 0.12 • Compositor: Hyprland direct scanout @ 120 FPS.\n- Cloud Leakage: **0 Bytes**. All local models, configurations, and user data stay on this machine.`;
      }

      const botMsg = document.createElement('div');
      botMsg.className = 'ai-chat-msg assistant';
      botMsg.innerHTML = `
        <div class="ai-avatar">🧠</div>
        <div class="ai-bubble"><strong>Praxis Local Intelligence:</strong><p class="ai-stream-text"></p></div>
      `;
      if (aiChatLog) {
        aiChatLog.appendChild(botMsg);
        aiChatLog.scrollTop = aiChatLog.scrollHeight;
      }

      const streamTarget = botMsg.querySelector('.ai-stream-text');
      let i = 0;
      const chunks = answer.split(' ');
      const streamTimer = setInterval(() => {
        if (i < chunks.length) {
          if (streamTarget) streamTarget.innerHTML += (i === 0 ? '' : ' ') + chunks[i];
          if (aiChatLog) aiChatLog.scrollTop = aiChatLog.scrollHeight;
          if (i % 3 === 0) playUiSound('type');
          i++;
        } else {
          clearInterval(streamTimer);
          playUiSound('focus');
        }
      }, 30);
    };

    if (aiInput) {
      aiInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
          window.askAiPrompt(aiInput.value);
          aiInput.value = '';
        }
      });
    }

    if (aiSendBtn) {
      aiSendBtn.addEventListener('click', () => {
        if (aiInput) {
          window.askAiPrompt(aiInput.value);
          aiInput.value = '';
        }
      });
    }

    if (aiMicBtn) {
      aiMicBtn.addEventListener('click', () => {
        playUiSound('chime');
        aiMicBtn.textContent = '🔴 Listening...';
        aiMicBtn.style.color = '#f7768e';
        notifySim('Whisper Audio: Recording local microphone buffer (Super+H)...');
        setTimeout(() => {
          aiMicBtn.textContent = '🎙️ Whisper';
          aiMicBtn.style.color = '';
          window.askAiPrompt('How does ZRAM prevent memory freeze?');
        }, 1400);
      });
    }

    // -----------------------------------------------------------------------
    // 9. Dual Boot Installer Simulation
    // -----------------------------------------------------------------------
    window.simulateInstallProgress = function () {
      playUiSound('click');
      const pBar = document.getElementById('sim-install-progress-bar');
      const pFill = document.getElementById('sim-progress-fill');
      const pLabel = document.getElementById('sim-progress-label');
      const runBtn = document.getElementById('sim-btn-run-install');
      if (!pBar || !pFill || !pLabel) return;

      pBar.style.display = 'flex';
      if (runBtn) runBtn.disabled = true;

      const steps = [
        { pct: 25, text: 'Step 1/4: Safely analyzing Windows 11 NTFS partition...', stepId: 'step-1' },
        { pct: 50, text: 'Step 2/4: Allocating 80 GB Btrfs subvolumes (@, @home)...', stepId: 'step-2' },
        { pct: 75, text: 'Step 3/4: Configuring ZRAM zstd compression module...', stepId: 'step-3' },
        { pct: 100, text: 'Step 4/4: Chaining systemd-boot with Windows Boot Manager!', stepId: 'step-4' }
      ];

      let cur = 0;
      function nextStep() {
        if (cur < steps.length) {
          const s = steps[cur];
          pFill.style.width = `${s.pct}%`;
          pLabel.textContent = s.text;
          document.querySelectorAll('.install-step').forEach(st => st.classList.remove('active'));
          const activeStep = document.getElementById(s.stepId);
          if (activeStep) activeStep.classList.add('active');
          playUiSound('type');
          cur++;
          setTimeout(nextStep, 1000);
        } else {
          playUiSound('chime');
          pLabel.textContent = '✔ Dual-Boot Ready! Windows & Praxis both safely configured.';
          notifySim('Installation Simulation Complete: Windows files intact, Praxis ready.');
          if (runBtn) {
            runBtn.disabled = false;
            runBtn.textContent = 'Installation Complete ✔';
          }
        }
      }
      nextStep();
    };

    // -----------------------------------------------------------------------
    // 10. Right-Click Desktop Context Menu
    // -----------------------------------------------------------------------
    const ctxMenu = document.getElementById('sim-context-menu');
    desktop.addEventListener('contextmenu', (e) => {
      if (e.target.closest('.sim-window-body') || e.target.closest('input')) return;
      e.preventDefault();
      playUiSound('click');
      if (!ctxMenu) return;

      const deskRect = desktop.getBoundingClientRect();
      let x = e.clientX - deskRect.left;
      let y = e.clientY - deskRect.top;

      if (x + 220 > desktop.clientWidth) x = desktop.clientWidth - 225;
      if (y + 260 > desktop.clientHeight) y = desktop.clientHeight - 265;

      ctxMenu.style.left = `${x}px`;
      ctxMenu.style.top = `${y}px`;
      ctxMenu.style.display = 'block';
    });

    document.addEventListener('click', (e) => {
      if (ctxMenu && !ctxMenu.contains(e.target)) {
        ctxMenu.style.display = 'none';
      }
    });

    // -----------------------------------------------------------------------
    // 11. Hero & Navigation "Try Simulator" Launchers
    // -----------------------------------------------------------------------
    const simLaunchTriggers = document.querySelectorAll('.btn-try-sim, .btn-sim-hero, .viewport-sim-launch');
    simLaunchTriggers.forEach((btn) => {
      btn.addEventListener('click', (e) => {
        const simSection = document.getElementById('simulator');
        if (simSection) {
          e.preventDefault();
          simSection.scrollIntoView({ behavior: 'smooth' });
          if (simWrapper) {
            simWrapper.classList.remove('highlight-focus');
            void simWrapper.offsetWidth;
            simWrapper.classList.add('highlight-focus');
          }
          playUiSound('chime');
          notifySim('Praxis Live Desktop active: All software environment is running!');
          toggleAppWindow('ai');
        }
      });
    });

    // -----------------------------------------------------------------------
    // 12. Fullscreen Mode
    // -----------------------------------------------------------------------
    if (fullscreenBtn && simWrapper) {
      fullscreenBtn.addEventListener('click', () => {
        simWrapper.classList.toggle('fullscreen-mode');
        const isFull = simWrapper.classList.contains('fullscreen-mode');
        fullscreenBtn.innerHTML = isFull
          ? `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M8 3v3a2 2 0 0 1-2 2H3m18 0h-3a2 2 0 0 1-2-2V3m0 18v-3a2 2 0 0 1 2-2h3M3 16h3a2 2 0 0 1 2 2v3"/></svg> Exit Fullscreen`
          : `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M8 3H5a2 2 0 0 0-2 2v3m18 0V5a2 2 0 0 0-2-2h-3m0 18h3a2 2 0 0 0 2-2v-3M3 16v3a2 2 0 0 0 2 2h3"/></svg> Fullscreen Simulator`;
      });
    }

    // -----------------------------------------------------------------------
    // 13. Toast Notification Helper
    // -----------------------------------------------------------------------
    function notifySim(msg) {
      const toast = document.getElementById('sim-toast');
      if (!toast) return;
      toast.textContent = msg;
      toast.classList.add('show');
      clearTimeout(toast._timer);
      toast._timer = setTimeout(() => {
        toast.classList.remove('show');
      }, 2800);
    }

    // -----------------------------------------------------------------------
    // 14. Global Keyboard Shortcuts in Simulator (Windows 11 Gestures & Keybinds)
    // -----------------------------------------------------------------------
    window.addEventListener('keydown', (e) => {
      if (!simWrapper.matches(':hover') && !simWrapper.classList.contains('fullscreen-mode')) return;

      if ((e.key === 'd' || e.key === 'D') && (e.metaKey || e.altKey)) {
        e.preventDefault();
        toggleShowDesktop();
      } else if (e.key === 'Tab' && (e.metaKey || e.altKey)) {
        e.preventDefault();
        if (standbyPanel) standbyPanel.classList.toggle('open');
        playUiSound('click');
        showSimToast('⊞ Standby Overview (Win+Tab)');
      } else if (e.key === 'ArrowLeft' && (e.metaKey || e.altKey)) {
        e.preventDefault();
        snapActiveWindow('left');
      } else if (e.key === 'ArrowRight' && (e.metaKey || e.altKey)) {
        e.preventDefault();
        snapActiveWindow('right');
      } else if (e.key === 'ArrowUp' && (e.metaKey || e.altKey)) {
        e.preventDefault();
        snapActiveWindow('max');
      } else if (e.key === 'ArrowDown' && (e.metaKey || e.altKey)) {
        e.preventDefault();
        snapActiveWindow('restore');
      } else if (e.key === ' ' && (e.metaKey || e.altKey)) {
        e.preventDefault();
        toggleAppWindow('ai');
      } else if (e.key === 'i' && (e.metaKey || e.altKey)) {
        e.preventDefault();
        toggleAppWindow('terminal');
      } else if (e.key === 'e' && (e.metaKey || e.altKey)) {
        e.preventDefault();
        toggleAppWindow('files');
      } else if (e.key === 'w' && (e.metaKey || e.altKey)) {
        e.preventDefault();
        toggleAppWindow('wallpapers');
      } else if (e.key === 'b' && (e.metaKey || e.altKey)) {
        e.preventDefault();
        toggleAppWindow('browser');
      } else if (e.key === 'g' && (e.metaKey || e.altKey)) {
        e.preventDefault();
        setProfile(activeProfile === 'Game Mode' ? 'Normal' : 'Game Mode');
      } else if (e.key === 'f' && !e.metaKey && !e.ctrlKey && document.activeElement.tagName !== 'INPUT') {
        e.preventDefault();
        if (fullscreenBtn) fullscreenBtn.click();
      } else if (e.key === 'Escape') {
        if (appDrawer) appDrawer.classList.remove('open');
        if (standbyPanel) standbyPanel.classList.remove('open');
        if (ctxMenu) ctxMenu.style.display = 'none';
      }
    });

    function escapeHtml(str) {
      if (!str) return '';
      return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    // Initial setup
    updateDockIndicators();
  }
})();
