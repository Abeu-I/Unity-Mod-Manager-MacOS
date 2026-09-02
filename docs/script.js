const root = document.documentElement;
const themeButton = document.querySelector('#theme-toggle');
const storedTheme = localStorage.getItem('adofai-theme');
const preferredTheme = window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark';

function setTheme(theme) {
  root.dataset.theme = theme;
  themeButton.setAttribute('aria-label', `Switch to ${theme === 'dark' ? 'light' : 'dark'} theme`);
}

setTheme(storedTheme || preferredTheme);
themeButton.addEventListener('click', () => {
  const next = root.dataset.theme === 'dark' ? 'light' : 'dark';
  setTheme(next);
  localStorage.setItem('adofai-theme', next);
});

const revealObserver = new IntersectionObserver((entries) => {
  entries.forEach((entry) => {
    if (entry.isIntersecting) {
      entry.target.classList.add('visible');
      revealObserver.unobserve(entry.target);
    }
  });
}, { threshold: 0.12 });

document.querySelectorAll('.reveal').forEach((element) => revealObserver.observe(element));

const compatibilityForm = document.querySelector('#compatibility-form');
const compatibilityResult = document.querySelector('#compatibility-result');

compatibilityForm.addEventListener('submit', (event) => {
  event.preventDefault();
  const data = new FormData(compatibilityForm);
  const chip = data.get('chip');
  const store = data.get('store');
  const isSteam = store === 'steam';
  const chipName = chip === 'apple' ? 'Apple Silicon' : 'Intel Mac';

  compatibilityResult.classList.toggle('warning', !isSteam);
  compatibilityResult.querySelector('.result-icon').textContent = isSteam ? '✓' : '!';
  compatibilityResult.querySelector('.result-label').textContent = isSteam ? 'READY TO MOD' : 'NOT VERIFIED';
  compatibilityResult.querySelector('h3').textContent = `${chipName} + ${isSteam ? 'Steam' : 'other store'}`;
  compatibilityResult.querySelector('p').textContent = isSteam
    ? (chip === 'apple'
      ? 'Supported through Rosetta 2. Steam Overlay, Workshop, achievements, and playtime remain connected.'
      : 'Supported natively on Intel. Launch through the normal Steam Play button to keep Steam features connected.')
    : 'This release is designed and tested specifically for the Steam macOS build of ADOFAI. Other releases may use different files and paths.';
  compatibilityResult.animate([
    { transform: 'scale(.985)', opacity: .65 },
    { transform: 'scale(1)', opacity: 1 }
  ], { duration: 280, easing: 'ease-out' });
});

const steps = [
  {
    count: 'STEP 01 / 04',
    title: 'Get the latest installer',
    body: 'Download the macOS ZIP from the latest GitHub release, then open it from your Downloads folder.',
    link: 'Open latest release',
    href: 'https://github.com/Abeu-I/Unity-Mod-Manager-MacOS/releases/latest',
    label: 'FILE TO LOOK FOR',
    code: 'ADOFAI-Mod-Installer-macOS.zip'
  },
  {
    count: 'STEP 02 / 04',
    title: 'Open the macOS app',
    body: 'Unzip the download, then open ADOFAI Mod Installer. If Gatekeeper asks, right-click the app and choose Open.',
    link: 'Read the source',
    href: 'https://github.com/Abeu-I/Unity-Mod-Manager-MacOS',
    label: 'APP NAME',
    code: 'ADOFAI Mod Installer.app'
  },
  {
    count: 'STEP 03 / 04',
    title: 'Press Install',
    body: 'The app detects your Steam game, checks requirements, creates backups, and installs the verified loader. Existing setups can be repaired or updated.',
    link: 'View installation guide',
    href: 'https://github.com/Abeu-I/Unity-Mod-Manager-MacOS#install',
    label: 'INSTALLER ACTION',
    code: 'Install / Repair or Update'
  },
  {
    count: 'STEP 04 / 04',
    title: 'Launch from Steam',
    body: 'Use the normal Steam Play button. Once ADOFAI opens, use the shortcut below to show or hide Unity Mod Manager.',
    link: 'Troubleshoot a problem',
    href: '#help',
    label: 'IN-GAME SHORTCUT',
    code: 'Control + F10'
  }
];

const stepButtons = [...document.querySelectorAll('[data-step]')];
const stepPanel = document.querySelector('#step-panel');

function selectStep(index) {
  const step = steps[index];
  stepButtons.forEach((button, buttonIndex) => {
    const selected = buttonIndex === index;
    button.setAttribute('aria-selected', selected);
    button.tabIndex = selected ? 0 : -1;
  });
  stepPanel.setAttribute('aria-labelledby', stepButtons[index].id);
  stepPanel.innerHTML = `
    <div>
      <span class="step-count">${step.count}</span>
      <h3>${step.title}</h3>
      <p>${step.body}</p>
      <a class="inline-link" href="${step.href}" ${step.href.startsWith('http') ? 'target="_blank" rel="noreferrer"' : ''}>${step.link} <span>${step.href.startsWith('http') ? '↗' : '↓'}</span></a>
    </div>
    <div class="step-command">
      <span>${step.label}</span>
      <code>${step.code}</code>
      <button class="copy-button" type="button" data-copy="${step.code}">Copy</button>
    </div>`;
  stepPanel.animate([
    { opacity: .4, transform: 'translateY(7px)' },
    { opacity: 1, transform: 'translateY(0)' }
  ], { duration: 240, easing: 'ease-out' });
}

stepButtons.forEach((button, index) => {
  button.addEventListener('click', () => selectStep(index));
  button.addEventListener('keydown', (event) => {
    if (!['ArrowLeft', 'ArrowRight'].includes(event.key)) return;
    event.preventDefault();
    const next = event.key === 'ArrowRight'
      ? (index + 1) % stepButtons.length
      : (index - 1 + stepButtons.length) % stepButtons.length;
    selectStep(next);
    stepButtons[next].focus();
  });
});

const toast = document.querySelector('#toast');
let toastTimer;
document.addEventListener('click', async (event) => {
  const copyButton = event.target.closest('[data-copy]');
  if (!copyButton) return;
  try {
    await navigator.clipboard.writeText(copyButton.dataset.copy);
    copyButton.textContent = 'Copied';
    clearTimeout(toastTimer);
    toast.classList.add('show');
    toastTimer = setTimeout(() => {
      toast.classList.remove('show');
      copyButton.textContent = 'Copy';
    }, 1800);
  } catch {
    copyButton.textContent = 'Select text';
  }
});

document.querySelectorAll('.filter').forEach((button) => {
  button.addEventListener('click', () => {
    const selected = button.dataset.filter;
    document.querySelectorAll('.filter').forEach((item) => item.classList.toggle('active', item === button));
    document.querySelectorAll('.mod-card').forEach((card) => {
      card.classList.toggle('hidden', selected !== 'all' && card.dataset.category !== selected);
    });
  });
});

document.querySelectorAll('.details-toggle').forEach((button) => {
  button.addEventListener('click', () => {
    const open = button.getAttribute('aria-expanded') === 'true';
    button.setAttribute('aria-expanded', String(!open));
  });
});

async function loadLatestRelease() {
  const label = document.querySelector('#release-label');
  const button = document.querySelector('#download-button');
  try {
    const response = await fetch('https://api.github.com/repos/Abeu-I/Unity-Mod-Manager-MacOS/releases/latest', {
      headers: { Accept: 'application/vnd.github+json' }
    });
    if (!response.ok) throw new Error('Release unavailable');
    const release = await response.json();
    label.textContent = release.tag_name || 'Latest release';
    const installer = release.assets?.find((asset) => /\.(dmg|zip)$/i.test(asset.name));
    if (installer) button.href = installer.browser_download_url;
  } catch {
    label.textContent = 'Latest release';
  }
}

loadLatestRelease();
