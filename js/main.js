/**
 * Praxis Linux (AIOS) — Main Client Script
 * Handles Interactive Terminal, Copy to Clipboard, FAQ Accordions,
 * Mobile Navigation, and Smooth Interactivity.
 */

(function () {
  'use strict';

  // -------------------------------------------------------------------------
  // Terminal Command Simulation Data
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

  // -------------------------------------------------------------------------
  // Terminal Tab Switching
  // -------------------------------------------------------------------------
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
  // Clipboard Copy Buttons with Visual Feedback
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
        // Fallback
        const textarea = document.createElement('textarea');
        textarea.value = textToCopy;
        document.body.appendChild(textarea);
        textarea.select();
        document.execCommand('copy');
        document.body.removeChild(textarea);
        alert('Copied to clipboard: ' + textToCopy);
      }
    });
  });

  // -------------------------------------------------------------------------
  // FAQ Accordion
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
  // Mobile Menu Toggle
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

  // Initial load
  updateTerminal('diagnostics');
})();
