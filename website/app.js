(() => {
  'use strict';
  document.getElementById('copyright-year').textContent = String(new Date().getFullYear());
  const match = location.pathname.match(/^\/u\/([a-z0-9_]{3,20})\/?$/i);
  if (!match) return;
  const username = match[1].toLowerCase();
  document.getElementById('home-page').hidden = true;
  document.getElementById('profile-page').hidden = false;
  document.querySelector('.nav-links').hidden = true;
  document.getElementById('profile-handle').textContent = `@${username}`;
  document.getElementById('profile-avatar').textContent = username[0].toUpperCase();
  document.title = `@${username} uitnodigen · Voxie`;
  const url = `https://voxie.online/u/${username}`;
  document.querySelector('meta[property="og:title"]').content = `@${username} op Voxie`;
  document.querySelector('meta[property="og:url"]').content = url;
  const open = document.getElementById('open-profile');
  // Universal links open from Messages and other apps; custom URL scheme lets
  // a person already browsing this same domain explicitly open the native app.
  open.href = `voxie://u/${username}`;
  const copy = document.getElementById('copy-profile');
  copy.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(url);
      copy.textContent = 'Link gekopieerd ✓';
    } catch {
      copy.textContent = url;
    }
  });
})();
