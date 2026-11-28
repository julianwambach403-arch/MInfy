// VR-Relais: Spielt YouTube/Twitch in einem normalen Tab ab, filmt den Tab
// (nur den Player-Bereich) und schickt ihn wie einen geteilten Bildschirm an alle in VR.
import { Net, RTC } from './net.js';
import { MediaController } from './media.js';

const $ = (s) => document.querySelector(s);
const room = (new URLSearchParams(location.search).get('room') || '').toUpperCase();
$('#room').textContent = room || '?';

const net = new Net();
let rtc = null;
let media = null;
let stream = null;

function status(text) { $('#status').textContent = text; }

function showMedia(m) {
  $('#idle').hidden = !!(m && m.kind !== 'video');
  if (m?.kind === 'video') $('#idle').textContent = 'Direkte Video-Links laufen in VR auch ohne Relais.';
  else $('#idle').textContent = 'Noch läuft kein YouTube- oder Twitch-Video im Raum.';
}

async function start() {
  if (!room) { status('Kein Raum angegeben. Öffne das Relais über die Lounge.'); return; }
  $('#btn-start').disabled = true;
  try {
    // Zuerst aufnehmen (braucht den frischen Klick), dann verbinden
    stream = await navigator.mediaDevices.getDisplayMedia({
      video: { frameRate: { ideal: 30, max: 30 }, width: { max: 1920 }, height: { max: 1080 } },
      audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false, suppressLocalAudioPlayback: true },
      preferCurrentTab: true, selfBrowserSurface: 'include', surfaceSwitching: 'exclude',
    });
    const vt = stream.getVideoTracks()[0];
    vt.contentHint = 'motion';
    if (window.CropTarget && vt.cropTo) {
      try { await vt.cropTo(await CropTarget.fromElement($('#player'))); } catch (e) { console.warn('Zuschneiden nicht möglich', e); }
    }
    vt.addEventListener('ended', stop);

    const welcome = await net.connect({ room, name: 'VR-Relais', color: '#ffffff', relay: true });
    rtc = new RTC(net, welcome.iceServers);
    rtc.screenBitrate = 6_000_000;
    rtc.setScreen(stream);
    for (const p of welcome.peers) if (!p.relay) rtc.addPeer(p.id, { sendMic: false });
    net.on('peer-join', ({ peer }) => { if (!peer.relay) rtc.addPeer(peer.id, { sendMic: false }); });
    net.on('peer-leave', ({ id }) => rtc.removePeer(id));
    net.on('disconnected', () => status('Verbindung getrennt. Fenster neu laden.'));

    media = new MediaController({ host: $('#host'), net });
    media.on('error', (m) => status(`⚠️ ${m}`));
    const onlyIframe = (m) => (m && m.kind !== 'video' ? m : null);
    media.apply(onlyIframe(welcome.media));
    showMedia(welcome.media);
    net.on('media', (m) => { media.apply(onlyIframe(m.media)); showMedia(m.media); });

    net.send({ t: 'state', screenId: stream.id, screenName: 'VR-Relais' });
    status(`📡 Relais läuft für Raum ${room}${stream.getAudioTracks().length ? '' : ' (ohne Ton: beim Teilen „Tab-Audio“ anhaken)'}`);
    $('#btn-start').hidden = true;
    $('#btn-stop').hidden = false;
  } catch (e) {
    status(e.name === 'NotAllowedError' ? 'Abgebrochen. Nochmal versuchen?' : `Fehler: ${e.message}`);
    $('#btn-start').disabled = false;
  }
}

function stop() {
  stream?.getTracks().forEach((t) => t.stop());
  net.ws?.close();
  status('Relais beendet. Du kannst dieses Fenster schließen.');
  $('#btn-stop').hidden = true;
}

$('#btn-start').onclick = start;
$('#btn-stop').onclick = stop;
