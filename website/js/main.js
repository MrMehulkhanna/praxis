/**
 * Praxis Linux (AIOS) — Main Client Script
 * Handles Interactive Terminal, 3D Camera Controls, Architecture Tabs,
 * Wallpaper Lightbox, Shortcuts Search Filter, Copy to Clipboard, and Mobile Navigation.
 */

(function () {
  'use strict';

  // -------------------------------------------------------------------------
  // 1. Terminal Command Simulation Data
  // -------------------------------------------------------------------------
  const terminalCommands = {
    diagnostics: {
      cmd: 'ai "why is my laptop hot?"',
      output: `[praxis-agent] Gathering real-time system telemetry...
● CPU: Intel Core i7-14700HX (20 threads) @ 4.6GHz — 68°C
● GPU: NVIDIA GeForce RTX 4060 Max-Q (60W) — 54°C (Normal)
● Memory: 3.4 GB / 32 GB used (ZRAM zstd compression: 0.1% thrash)
● Process analysis:
    PID 4821 [blender] consuming 480% CPU (rendering frame 42)
    PID 1120 [praxis-daemon] idle @ 0.2% CPU
✔ Diagnosis:
  Your laptop is running Blender in the background. The thermal system is performing normally within safety margins.
  Recommendation: Run 'praxis mode game on' to prioritize render threads, or tap Super+G.`
    },
    voice: {
      cmd: 'Super+H [Hold & Speak] -> "Add a retry decorator with exponential backoff to fetch_data"',
      output: `[praxis-dictate] Local Whisper Small (English) — Zero cloud latency
Transcribed in 142ms:
"Add a retry decorator with exponential backoff to fetch_data"
✔ Streamed directly into active NeoVim buffer at cursor (line 84).
No data left your hardware.`
    },
    doctor: {
      cmd: 'praxis doctor --fix',
      output: `[praxis-doctor] Running comprehensive hardware & kernel audit...
✔ [OK] UEFI Bootloader: Praxis priority confirmed in NVRAM
✔ [OK] HP/Acer Fallback Loader: Verified at /boot/EFI/BOOT/BOOTX64.EFI
✔ [OK] Backlight Engine: nvidia_wmi_ec_backlight active (PWM clamped > 3%)
✔ [OK] Bluetooth Agent: org.bluez.Agent1 registered with PIN prompt helper
✔ [OK] Wayland Display: Hyprland 120Hz smooth rendering (no Aquamarine blit crash)
✔ [FIXED] Mirror list ranked: top 5 fastest mirrors synchronized
All 18 system subsystems healthy. Zero errors.`
    },
    rag: {
      cmd: 'ai rag add ~/research && ai rag q "What was our quarterly GPU memory budget?"',
      output: `[praxis-rag] Embedding 42 PDF & Markdown documents using local MiniLM...
Indexed in 1.4s (FTS5 + Vector hybrid store in local SQLite).
Query: "What was our quarterly GPU memory budget?"
✔ Answer:
  "According to internal-benchmarks.md (p. 4), the maximum local VRAM ceiling is 4.8 GB, leaving at least 1.2 GB reserved for Wayland desktop compositing."
Sources:
  1. ~/research/q3-architecture.pdf (Score: 0.94)
  2. ~/research/internal-benchmarks.md (Score: 0.91)`
    }
  };

  // Terminal Tab Switching
  const tabBtns = document.querySelectorAll('.tab-btn');
  const terminalPromptCmd = document.getElementById('terminal-cmd-text');
  const terminalOutput = document.getElementById('terminal-output-text');

  function updateTerminal(key) {
    const data = terminalCommands[key];
    if (!data || !terminalPromptCmd || !terminalOutput) return;

    terminalPromptCmd.textContent = data.cmd;
    terminalOutput.textContent = data.output;
  }

  tabBtns.forEach((btn) => {
    btn.addEventListener('click', () => {
      tabBtns.forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      const tabKey = btn.getAttribute('data-tab');
      updateTerminal(tabKey);
    });
  });

  // -------------------------------------------------------------------------
  // 2. 3D WebGL Camera Controls
  // -------------------------------------------------------------------------
  const viewBtns = document.querySelectorAll('[data-view]');
  viewBtns.forEach((btn) => {
    btn.addEventListener('click', () => {
      viewBtns.forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      const view = btn.getAttribute('data-view');
      if (view === 'spin') {
        if (typeof window.togglePraxisAutoSpin === 'function') {
          const isSpinning = window.togglePraxisAutoSpin();
          btn.innerHTML = isSpinning ? '<span>Spinning ⚡</span>' : '<span>Auto-Spin</span>';
        }
      } else if (typeof window.setPraxis3DView === 'function') {
        window.setPraxis3DView(view);
      }
    });
  });

  // -------------------------------------------------------------------------
  // 3. Architecture Deep-Dive Tabs
  // -------------------------------------------------------------------------
  const archTabBtns = document.querySelectorAll('.arch-tab-btn');
  const archPanels = document.querySelectorAll('.arch-panel');

  archTabBtns.forEach((btn) => {
    btn.addEventListener('click', () => {
      archTabBtns.forEach((b) => b.classList.remove('active'));
      archPanels.forEach((p) => p.classList.remove('active'));

      btn.classList.add('active');
      const target = btn.getAttribute('data-arch-target');
      const panel = document.getElementById(target);
      if (panel) {
        panel.classList.add('active');
      }
    });
  });

  // -------------------------------------------------------------------------
  // 4. Searchable Shortcuts Matrix
  // -------------------------------------------------------------------------
  const searchInput = document.getElementById('shortcut-search-input');
  const catFilterBtns = document.querySelectorAll('.shortcut-cat-btn');
  const shortcutRows = document.querySelectorAll('.shortcut-row');

  let activeCategory = 'all';

  function filterShortcuts() {
    const query = searchInput ? searchInput.value.toLowerCase().trim() : '';

    shortcutRows.forEach((row) => {
      const cat = row.getAttribute('data-category') || '';
      const text = row.textContent.toLowerCase();

      const matchesCat = activeCategory === 'all' || cat === activeCategory;
      const matchesQuery = query === '' || text.includes(query);

      if (matchesCat && matchesQuery) {
        row.style.display = 'grid';
      } else {
        row.style.display = 'none';
      }
    });
  }

  if (searchInput) {
    searchInput.addEventListener('input', filterShortcuts);
  }

  catFilterBtns.forEach((btn) => {
    btn.addEventListener('click', () => {
      catFilterBtns.forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      activeCategory = btn.getAttribute('data-cat') || 'all';
      filterShortcuts();
    });
  });

  // -------------------------------------------------------------------------
  // 5. Wallpaper Lightbox Preview
  // -------------------------------------------------------------------------
  const wallpaperCards = document.querySelectorAll('.wallpaper-card');
  const modal = document.getElementById('wallpaper-modal');
  const modalImg = document.getElementById('modal-wallpaper-img');
  const modalTitle = document.getElementById('modal-wallpaper-title');
  const modalClose = document.getElementById('modal-close-btn');

  wallpaperCards.forEach((card) => {
    card.addEventListener('click', () => {
      const src = card.getAttribute('data-full-img');
      const title = card.getAttribute('data-wallpaper-title');
      if (modal && modalImg && modalTitle) {
        modalImg.src = src;
        modalTitle.textContent = title;
        modal.classList.add('open');
      }
    });
  });

  if (modalClose && modal) {
    modalClose.addEventListener('click', () => {
      modal.classList.remove('open');
    });
    modal.addEventListener('click', (e) => {
      if (e.target === modal) {
        modal.classList.remove('open');
      }
    });
  }

  // -------------------------------------------------------------------------
  // 6. Clipboard Copy Buttons with Visual Feedback
  // -------------------------------------------------------------------------
  const copyButtons = document.querySelectorAll('[data-copy]');

  copyButtons.forEach((btn) => {
    btn.addEventListener('click', async () => {
      const textToCopy = btn.getAttribute('data-copy');
      if (!textToCopy) return;

      try {
        await navigator.clipboard.writeText(textToCopy);
        const originalText = btn.innerHTML;
        btn.innerHTML = `<span style="color: #10b981; font-weight: bold;">✔ Copied!</span>`;
        setTimeout(() => {
          btn.innerHTML = originalText;
        }, 2200);
      } catch (err) {
        const textarea = document.createElement('textarea');
        textarea.value = textToCopy;
        document.body.appendChild(textarea);
        textarea.select();
        document.execCommand('copy');
        document.body.removeChild(textarea);
        alert('Copied: ' + textToCopy);
      }
    });
  });

  // -------------------------------------------------------------------------
  // 7. FAQ Accordion
  // -------------------------------------------------------------------------
  const faqItems = document.querySelectorAll('.faq-item');

  faqItems.forEach((item) => {
    const questionBtn = item.querySelector('.faq-question');
    if (!questionBtn) return;

    questionBtn.addEventListener('click', () => {
      const isActive = item.classList.contains('active');
      faqItems.forEach((f) => f.classList.remove('active'));
      if (!isActive) {
        item.classList.add('active');
      }
    });
  });

  // -------------------------------------------------------------------------
  // 8. Mobile Menu Toggle
  // -------------------------------------------------------------------------
  const mobileBtn = document.querySelector('.mobile-menu-btn');
  const navLinks = document.querySelector('.nav-links');

  if (mobileBtn && navLinks) {
    mobileBtn.addEventListener('click', () => {
      const isVisible = navLinks.style.display === 'flex';
      navLinks.style.display = isVisible ? 'none' : 'flex';
      if (!isVisible) {
        navLinks.style.flexDirection = 'column';
        navLinks.style.position = 'absolute';
        navLinks.style.top = '72px';
        navLinks.style.left = '0';
        navLinks.style.right = '0';
        navLinks.style.background = '#090c14';
        navLinks.style.padding = '24px';
        navLinks.style.borderBottom = '1px solid rgba(255, 255, 255, 0.1)';
      }
    });
  }

  // -------------------------------------------------------------------------
  // 9. Releases & Version Archive Filters & Changelogs
  // -------------------------------------------------------------------------
  const releaseFilterBtns = document.querySelectorAll('.release-filter-btn');
  const releaseCards = document.querySelectorAll('.release-card');

  releaseFilterBtns.forEach((btn) => {
    btn.addEventListener('click', () => {
      releaseFilterBtns.forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      const filter = btn.getAttribute('data-filter');

      releaseCards.forEach((card) => {
        const cardType = card.getAttribute('data-type');
        if (filter === 'all' || filter === cardType) {
          card.style.display = 'block';
        } else {
          card.style.display = 'none';
        }
      });
    });
  });

  const releaseNotesBtns = document.querySelectorAll('.release-notes-btn');
  releaseNotesBtns.forEach((btn) => {
    btn.addEventListener('click', () => {
      const content = btn.nextElementSibling;
      if (!content) return;
      content.classList.toggle('open');
      const icon = btn.querySelector('svg');
      if (icon) {
        icon.style.transform = content.classList.contains('open') ? 'rotate(180deg)' : 'rotate(0deg)';
        icon.style.transition = 'transform 0.2s ease';
      }
    });
  });

  // Initial load
  updateTerminal('diagnostics');
})();
