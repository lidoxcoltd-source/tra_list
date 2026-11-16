import React, { useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { initializeApp, getApps } from 'firebase/app';
import { getFirestore, doc, getDocFromServer, setDoc, increment } from 'firebase/firestore';

const h = React.createElement;
const firebaseConfig = {
  apiKey: 'AIzaSyAHfS7iNK-tNEesHkbE_79cfdEEbLX1x6A',
  appId: '1:903048450592:web:f9d6d50a3955d20c876245',
  messagingSenderId: '903048450592',
  projectId: 'tra-verify',
  authDomain: 'tra-verify.firebaseapp.com',
  storageBucket: 'tra-verify.firebasestorage.app',
};
const db = getFirestore(getApps().length ? getApps()[0] : initializeApp(firebaseConfig));
const platforms = [
  { id: 'playstore', icon: '▶', name: 'Google Play', detail: 'For Android phones & tablets', color: 'green', fallback: '' },
  { id: 'appstore', icon: '●', name: 'App Store', detail: 'For iPhone & iPad', color: 'light', fallback: '' },
  { id: 'apk', icon: '⬇', name: 'Android APK', detail: 'Direct install package', color: 'lime', fallback: '' },
  { id: 'windows', icon: '▦', name: 'Windows', detail: 'For desktop computers', color: 'blue', fallback: '' },
  { id: 'web', icon: '↗', name: 'Open the web app', detail: 'Start instantly in your browser', color: 'orange', fallback: '/' },
];
const features = [
  ['01', 'Sell with confidence', 'Create polished invoices, quotations and verified receipts in seconds.'],
  ['02', 'Know your numbers', 'Follow income, expenses, inventory and customer balances in one place.'],
  ['03', 'Work as a team', 'Give your staff the access they need and keep every shop in sync.'],
];
const fallbackCenter = { title: 'Business, in motion.', subtitle: 'The tools you need to run a sharper business, wherever work takes you.', eyebrow: 'A SMARTER WAY TO WORK' };
const txt = (en, sw, isSw) => isSw ? sw : en;

function App() {
  const [sw, setSw] = useState(() => localStorage.getItem('downloads_lang') === 'sw' || (!localStorage.getItem('downloads_lang') && (/^sw/i.test(navigator.language) || /-TZ$/i.test(navigator.language))));
  const [center, setCenter] = useState(fallbackCenter);
  const [items, setItems] = useState({});
  const [plan, setPlan] = useState({ amount: 20000, durationDays: 365 });
  const [visitCount, setVisitCount] = useState(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let disposed = false;
    const visitKey = 'downloads_last_visit';
    const today = new Date().toISOString().slice(0, 10);
    const isNewVisit = localStorage.getItem(visitKey) !== today;
    if (isNewVisit) localStorage.setItem(visitKey, today);
    const loadPublicConfig = async () => {
      try {
        const snapshot = await getDocFromServer(doc(db, 'app_config', 'download_center'));
        if (disposed) return;
        if (snapshot.exists()) {
          const data = snapshot.data();
          setCenter({ ...fallbackCenter, ...data });
          setItems(data.items && typeof data.items === 'object' ? data.items : {});
        }
        setFailed(false);
      } catch (error) {
        console.error('Could not load public download links from Firestore:', error);
        if (!disposed) setFailed(true);
      }
      try {
        const snapshot = await getDocFromServer(doc(db, 'app_config', 'subscription_plan'));
        if (!disposed && snapshot.exists()) setPlan(p => ({ ...p, ...snapshot.data() }));
      } catch (error) {
        console.warn('Could not load public subscription pricing:', error);
      }
      try {
        if (isNewVisit) await bump('visits');
        const snapshot = await getDocFromServer(doc(db, 'downloadStats', 'visits'));
        if (!disposed) setVisitCount(snapshot.exists() ? Number(snapshot.data().count) || 0 : 0);
      } catch (error) {
        console.warn('Could not load public downloads visit count:', error);
      }
    };
    void loadPublicConfig();
    const observer = new IntersectionObserver(entries => entries.forEach(e => { if (e.isIntersecting) { e.target.classList.add('shown'); observer.unobserve(e.target); } }), { threshold: .12 });
    document.querySelectorAll('.reveal').forEach(el => observer.observe(el));
    return () => { disposed = true; observer.disconnect(); };
  }, []);
  const bump = key => setDoc(doc(db, 'downloadStats', key), { count: increment(1) }, { merge: true }).catch(() => {});
  const choose = p => {
    const item = items[p.id] || {};
    const target = p.id === 'web' ? ((item.enabled && item.url?.startsWith('https://') && !item.url.includes('downloads')) ? item.url : '/') : (item.enabled && item.url?.startsWith('https://') ? item.url : p.fallback);
    if (target) { bump(`click_${p.id}`); window.location.href = target; }
  };
  const go = id => document.getElementById(id)?.scrollIntoView({ behavior: 'smooth' });
  const toggleLang = () => { const next = !sw; setSw(next); localStorage.setItem('downloads_lang', next ? 'sw' : 'en'); document.documentElement.lang = next ? 'sw' : 'en'; };
  const price = new Intl.NumberFormat(sw ? 'sw-TZ' : 'en-US').format(plan.amount || 20000);
  const duration = plan.durationDays || 365;
  const period = duration === 365 ? txt('per year', 'kwa mwaka', sw) : duration === 30 ? txt('per month', 'kwa mwezi', sw) : txt(`per ${duration} days`, `kwa siku ${duration}`, sw);

  return h('main', { className: 'site-shell' },
    h('div', { className: 'ambient ambient-one' }), h('div', { className: 'ambient ambient-two' }),
    h('header', { className: 'nav wrap' }, h('a', { className: 'brand', href: '/', 'aria-label': 'MJASI POS home' }, h('img', { src: '/mjas.png', alt: '' }), h('span', null, 'MJASI', h('i', { className: 'brand-dot' }, '.'))),
      h('nav', null, h('button', { onClick: () => go('features') }, txt('Features', 'Vipengele', sw)), h('button', { onClick: () => go('pricing') }, txt('Pricing', 'Bei', sw)), h('button', { onClick: () => go('platforms') }, txt('Downloads', 'Pakua', sw))),
      h('div', { className: 'nav-actions' }, h('button', { className: 'lang', onClick: toggleLang }, sw ? 'EN' : 'SW'), h('button', { className: 'nav-cta', onClick: () => go('platforms') }, txt('Get the app', 'Pata app', sw), h('span', null, '↗')))),
    h('section', { className: 'hero wrap' },
      h('div', { className: 'hero-copy' }, h('div', { className: 'eyebrow' }, h('span', { className: 'eyebrow-line' }), center.eyebrow),
        h('h1', null, txt('Run your business.', 'Simamia biashara.', sw), h('br'), h('span', { className: 'gradient-text' }, txt('On your terms.', 'Kwa namna yako.', sw))),
        h('p', { className: 'hero-subtitle' }, txt(center.subtitle, 'Zana unazohitaji kusimamia biashara kwa urahisi, popote ulipo.', sw)),
        h('div', { className: 'hero-actions' }, h('button', { className: 'primary-btn', onClick: () => go('platforms') }, txt('Choose your platform', 'Chagua kifaa chako', sw), h('span', null, '↗')), h('span', { className: 'microcopy' }, h('span', { className: 'online-dot' }), txt('Made for ambitious businesses', 'Imeundwa kwa biashara zinazokua', sw))),
        h('div', { className: 'hero-proof' }, h('div', { className: 'proof-avatars' }, h('i', null, 'M'), h('i', null, 'J'), h('i', null, 'P')), h('span', null, txt('Everything your business needs, connected.', 'Kila kitu cha biashara yako, kimeunganishwa.', sw)))),
      h('div', { className: 'hero-visual' }, h('div', { className: 'orbit orbit-a' }), h('div', { className: 'orbit orbit-b' }), h('div', { className: 'hero-glow' }),
        h('div', { className: 'device device-back' }, h('div', { className: 'device-top' }), h('div', { className: 'back-ui' }, h('div', { className: 'ui-line short' }), h('div', { className: 'ui-line' }), h('div', { className: 'chart' }, h('i'), h('i'), h('i'), h('i'), h('i'), h('i'), h('i')), h('div', { className: 'ui-line' }), h('div', { className: 'ui-line short' }))),
        h('div', { className: 'device device-front' }, h('div', { className: 'device-notch' }), h('div', { className: 'phone-ui' }, h('div', { className: 'phone-greeting' }, h('small', null, txt('GOOD MORNING', 'HABARI ZA ASUBUHI', sw)), h('b', null, 'Karibu, Amina'), h('span', null, '●  Your business is thriving')), h('div', { className: 'balance-card' }, h('small', null, 'TOTAL SALES'), h('strong', null, 'TSh 2,840,000'), h('span', null, '↗  12.8% this week')), h('div', { className: 'phone-row' }, h('span', null, 'Recent activity'), h('small', null, 'View all  ↗')), h('div', { className: 'activity' }, h('i', null, '↗'), h('span', null, h('b', null, 'New invoice paid'), h('small', null, 'Today · 10:42 AM')), h('strong', null, '+ TSh 240k')), h('div', { className: 'activity' }, h('i', { className: 'purple' }, '▤'), h('span', null, h('b', null, 'Stock received'), h('small', null, 'Today · 9:18 AM')), h('strong', null, '12 items')))),
        h('div', { className: 'float-chip chip-sales' }, h('span', null, '↗'), h('div', null, h('small', null, 'THIS MONTH'), h('b', null, '+24.8%'))), h('div', { className: 'float-chip chip-sync' }, h('span', null, '✦'), h('div', null, h('small', null, 'ALL SYSTEMS'), h('b', null, 'In sync'))))),
    h('div', { className: 'trust-strip wrap' }, h('span', null, txt('ONE WORKSPACE. EVERY DEVICE.', 'NAFASI MOJA. KILA KIFAA.', sw)), h('div', null, 'ANDROID', h('i'), ' IOS', h('i'), ' WINDOWS', h('i'), ' WEB')),
    h('section', { className: 'section wrap', id: 'features' }, h('div', { className: 'section-head reveal' }, h('div', { className: 'eyebrow' }, '01 — BUILT FOR THE WAY YOU WORK'), h('h2', null, txt('Less admin. ', 'Kazi rahisi. ', sw), h('span', { className: 'gradient-text' }, txt('More momentum.', 'Maendeleo zaidi.', sw)), h('p', null, txt('The everyday tools that give you clarity, control, and room to grow.', 'Zana za kila siku zinazokupa uwazi, udhibiti na nafasi ya kukua.', sw))),
      h('div', { className: 'feature-grid' }, ...features.map((f, i) => h('article', { className: `feature-card reveal delay-${i}`, key: f[0] }, h('div', { className: 'feature-top' }, h('span', null, f[0]), h('i', null, ['↗', '◌', '⌘'][i])), h('div', { className: 'feature-rule' }), h('h3', null, txt(f[1], ['Uza kwa uhakika', 'Elewa takwimu', 'Fanya kazi pamoja'][i], sw)), h('p', null, txt(f[2], ['Tengeneza ankara, nukuu na risiti zilizothibitishwa kwa sekunde.', 'Fuatilia mapato, matumizi, bidhaa na madeni sehemu moja.', 'Wape wafanyakazi ruhusa sahihi na uunganishe maduka yote.'][i], sw))))),
    h('section', { className: 'platform-section', id: 'platforms' }, h('div', { className: 'wrap platform-inner' }, h('div', { className: 'section-head reveal' }, h('div', { className: 'eyebrow' }, '02 — YOUR BUSINESS, YOUR DEVICE'), h('h2', null, txt('Pick your ', 'Chagua ', sw), h('span', { className: 'gradient-text' }, txt('starting point.', 'unapoanzia.', sw)), h('p', null, txt('One account. A seamless experience, wherever the day takes you.', 'Akaunti moja. Uzoefu rahisi, popote siku inakupeleka.', sw))),
      failed && h('div', { className: 'notice', role: 'status' }, txt('Download links could not be loaded from the server. Refresh this page to try again.', 'Viungo vya upakuaji havikuweza kupakiwa kutoka kwenye seva. Onyesha upya ukurasa ujaribu tena.', sw)),
      h('div', { className: 'platform-grid' }, ...platforms.map((p, i) => { const item = items[p.id] || {}; const available = p.id === 'web' || item.enabled; return h('button', { className: `platform-card ${p.color} reveal delay-${Math.min(i, 2)}`, key: p.id, onClick: () => choose(p), disabled: !available && !p.fallback }, h('span', { className: 'platform-icon' }, p.icon), h('span', { className: 'platform-copy' }, h('b', null, txt(p.name, ['Google Play', 'App Store', 'Android APK', 'Windows', 'Fungua web app'][i], sw)), h('small', null, txt(p.detail, ['Kwa simu na tableti za Android', 'Kwa iPhone na iPad', 'Pakua na usakinishe moja kwa moja', 'Kwa kompyuta', 'Anza sasa kwenye kivinjari'][i], sw)), item.version && h('small', { className: 'version' }, `VERSION ${item.version}`)), h('span', { className: 'platform-arrow' }, available ? '↗' : '→')); })),
      h('div', { className: 'platform-foot reveal' }, h('span', null, '✦'), txt('Your business data stays in sync across your devices.', 'Taarifa za biashara yako zinasawazishwa kwenye vifaa vyako.', sw),
        visitCount !== null && h('span', { className: 'visit-counter', 'aria-live': 'polite', style: { marginLeft: 'auto', color: 'var(--mint)', fontSize: '12px', whiteSpace: 'nowrap' } }, `${new Intl.NumberFormat(sw ? 'sw-TZ' : 'en-US').format(visitCount)} ${txt('total visits', 'jumla ya ziara', sw)}`)))),
    h('section', { className: 'pricing-section wrap', id: 'pricing' }, h('div', { className: 'pricing-copy reveal' }, h('div', { className: 'eyebrow' }, '03 — CLEAR, SIMPLE PRICING'), h('h2', null, txt('One plan. ', 'Mpango mmoja. ', sw), h('span', { className: 'gradient-text' }, txt('Everything included.', 'Kila kitu ndani yake.', sw)), h('p', null, txt('Straightforward pricing so you can focus on what matters: building your business.', 'Bei iliyo wazi ili uangalie jambo muhimu: kukuza biashara yako.', sw))),
      h('div', { className: 'price-card reveal delay-1' }, h('div', { className: 'price-card-top' }, h('span', null, 'MJASI POS'), h('span', { className: 'plan-badge' }, 'PRO')), h('div', { className: 'price-amount' }, h('small', null, 'TSh'), h('strong', null, price)), h('div', { className: 'price-period' }, period), h('div', { className: 'price-divider' }), ...['Unlimited invoices, quotations & receipts', 'Staff accounts with permissions', 'Income, expense & debt tracking', 'Cloud sync across all your devices', '11 professional document designs'].map((x, i) => h('div', { className: 'perk', key: x }, h('span', null, '✓'), txt(x, ['Ankara, nukuu na risiti bila kikomo', 'Akaunti za wafanyakazi zenye ruhusa', 'Ufuatiliaji wa mapato, matumizi na madeni', 'Usawazishaji kwenye vifaa vyako', 'Miundo 11 ya nyaraka za kitaalamu'][i], sw))), h('button', { className: 'primary-btn price-btn', onClick: () => go('platforms') }, txt('Get started', 'Anza sasa', sw), h('span', null, '↗')), h('small', { className: 'price-note' }, txt('Secure payments · Cancel anytime', 'Malipo salama · Sitisha wakati wowote', sw)))),
    h('footer', { className: 'footer wrap' }, h('a', { className: 'brand', href: '/' }, h('img', { src: '/mjas.png', alt: '' }), h('span', null, 'MJASI', h('i', { className: 'brand-dot' }, '.'))), h('span', null, `© ${new Date().getFullYear()} MJASI POS · ${txt('Built for business.', 'Imeundwa kwa biashara.', sw)}`), h('a', { href: '/', className: 'footer-link' }, txt('Open web app', 'Fungua web app', sw), ' ↗'))
  );
}

createRoot(document.getElementById('root')).render(h(App));
