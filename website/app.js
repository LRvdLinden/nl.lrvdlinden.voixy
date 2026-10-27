(() => {
  'use strict';
  // Explicit Netherlands device locale => Dutch; all other regions default English.
  // Visitors may always override the choice, including on shared/profile links.
  const locale = navigator.language || '';
  const stored = (() => { try { return localStorage.getItem('voxie.site.language'); } catch { return null; } })();
  let language = stored === 'nl' || stored === 'en' ? stored : (/-NL$/i.test(locale) ? 'nl' : 'en');
  const translations = new Map(Object.entries({
    'Hoofdnavigatie':'Main navigation','Hoe het werkt':'How it works','Waarom Voxie':'Why Voxie','Binnenkort beschikbaar':'Coming soon',
    'WALKIETALKIE, MAAR DAN OPNIEUW':'THE WALKIE-TALKIE, REIMAGINED',
    'Soms is praten':'Sometimes talking','alles wat nodig is.':'is all it takes.',
    'Geen getyp. Geen gedoe. Kies een vriend, houd de knop ingedrukt en laat je stem spreken. Gewoon direct, via je iPhone, iPad of Apple Watch.':'No typing. No fuss. Pick a friend, hold the button and let your voice do the talking. Instantly, on your iPhone, iPad or Apple Watch.',
    'Ontdek Voxie':'Discover Voxie','Binnenkort in de App Store':'Coming soon to the App Store',
    'GEMAAKT VOOR':'BUILT FOR','JOUW PROFIEL':'YOUR PROFILE','BESCHIKBAAR':'AVAILABLE','VRIENDEN':'FRIENDS','UITNODIGEN':'INVITE',
    'Beschikbaar':'Available','KIES EEN VRIEND OM TE PRATEN':'SELECT A FRIEND TO TALK','HOUD VAST':'PRESS AND HOLD',
    'CONCEPTSCHERMEN · IPHONE EN APPLE WATCH':'CONCEPT SCREENS · IPHONE AND APPLE WATCH',
    'CONCEPTSCHERMEN · IPHONE · IPAD · APPLE WATCH':'CONCEPT SCREENS · IPHONE · IPAD · APPLE WATCH',
    '01 / ZO WERKT HET':'01 / HOW IT WORKS','Minder tikken.':'Less typing.','Meer zeggen.':'More talking.',
    'Een gesprek beginnen zou niet moeilijker moeten zijn dan op een knop drukken.':'Starting a conversation should be as simple as pressing a button.',
    'Vind je mensen.':'Find your people.','Maak een profiel met je eigen unieke gebruikersnaam. Nodig vrienden uit via hun naam of een persoonlijke profiellink.':'Create a profile with a unique username. Invite friends by username or a personal profile link.',
    'Kies met wie.':'Choose your friend.','Open een vriend en je bent klaar om te praten. Geen groepsgesprekken, geen ruis. Alleen jullie twee.':'Choose a friend and you’re ready to talk. No group calls, no distractions. Just the two of you.',
    'Druk en praat.':'Press and talk.','Houd de gele knop ingedrukt. Spreek. Laat los. Je stem komt direct bij je vriend aan.':'Hold the yellow button. Speak. Release. Your friend hears you right away.',
    '02 / OP JOUW MANIER':'02 / YOUR WAY','Op je pols.':'On your wrist.','In je hand.':'In your hand.','Altijd dichtbij.':'Always close.',
    'Voxie is gemaakt voor Apple Watch én iPhone. Jij bepaalt waar je stemmen ontvangt: op je Watch, op je iPhone of op allebei.':'Voxie is built for Apple Watch, iPhone and iPad. You choose where to receive voices: your Watch, phone, or both.',
    'Vrienden uitnodigen en accepteren':'Invite and accept friends','Eén profiel op je apparaten':'One profile across your devices',
    'Alleen een praatknop wanneer je een vriend kiest':'A talk button only after selecting a friend',
    'Omdat sommige dingen':'Because some things','lekkerder klinken dan ze lezen.':'sound better than they read.',
    'VOXIE VOOR APPLE-APPARATEN':'VOXIE FOR APPLE DEVICES','De stem van straks.':'The voice of tomorrow.','Binnenkort hier.':'Coming soon.',
    'Voxie verschijnt binnenkort in de App Store voor iPhone, iPad en Apple Watch.':'Voxie is coming soon to the App Store for iPhone, iPad and Apple Watch.',
    'BINNENKORT VERKRIJGBAAR IN':'COMING SOON TO THE','De App Store-link verschijnt zodra Voxie beschikbaar is.':'The App Store link will appear when Voxie launches.',
    'IEMAND WIL MET JE PRATEN':'SOMEONE WANTS TO TALK','Maak verbinding met':'Connect with',
    'Je hebt een Voxie-profiel ontvangen. Open Voxie en bevestig dat je een vriendschapsverzoek naar deze persoon wilt sturen.':'Someone shared a Voxie profile with you. Open Voxie to send them a friend request.',
    'Open in Voxie':'Open in Voxie','Kopieer profiellink':'Copy profile link',
    'Voxie nog niet geïnstalleerd? De app komt binnenkort beschikbaar in de App Store.':'Don’t have Voxie yet? It’s coming soon to the App Store.',
    'Say it. Don\'t type it.':'Say it. Don\'t type it.'
  }));
  // Retain the original Dutch content so switching languages never accumulates changes.
  const nodes = [];
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  while (walker.nextNode()) {
    const node = walker.currentNode;
    const match = node.textContent.match(/^(\s*)(.*?)(\s*)$/s);
    if (match && translations.has(match[2])) nodes.push({ node, original: match[2], before: match[1], after: match[3] });
  }
  const originalTitle = document.title;
  const originalDescription = document.querySelector('meta[name="description"]').content;
  const originalOgDescription = document.querySelector('meta[property="og:description"]').content;
  function applyLanguage() {
    document.documentElement.lang = language;
    nodes.forEach(({node, original, before, after}) => { node.textContent = before + (language === 'en' ? translations.get(original) : original) + after; });
    document.title = language === 'en' ? 'Voxie — Walkie-talkie, reimagined' : originalTitle;
    document.querySelector('meta[name="description"]').content = language === 'en' ? 'Voxie brings the walkie-talkie to iPhone, iPad and Apple Watch. Coming soon to the App Store.' : originalDescription;
    document.querySelector('meta[property="og:description"]').content = language === 'en' ? 'One press. Instantly connected. Coming soon for iPhone, iPad and Apple Watch.' : originalOgDescription;
    document.getElementById('language-switch').textContent = language === 'nl' ? 'EN' : 'NL';
  }
  document.getElementById('language-switch').addEventListener('click', () => {
    language = language === 'nl' ? 'en' : 'nl';
    try { localStorage.setItem('voxie.site.language', language); } catch { /* private mode */ }
    applyLanguage();
  });
  applyLanguage();
  document.getElementById('copyright-year').textContent = String(new Date().getFullYear());
  const match = location.pathname.match(/^\/u\/([a-z0-9_]{3,20})\/?$/i);
  if (!match) return;
  const username = match[1].toLowerCase();
  document.getElementById('home-page').hidden = true;
  document.getElementById('profile-page').hidden = false;
  document.querySelector('.nav-links').hidden = true;
  document.getElementById('profile-handle').textContent = `@${username}`;
  document.getElementById('profile-avatar').textContent = username[0].toUpperCase();
  document.title = language === 'nl' ? `@${username} uitnodigen · Voxie` : `Invite @${username} · Voxie`;
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
      copy.textContent = language === 'nl' ? 'Link gekopieerd' : 'Link copied';
    } catch {
      copy.textContent = url;
    }
  });
})();
