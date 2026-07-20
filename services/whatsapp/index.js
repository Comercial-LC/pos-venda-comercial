// Carrega .env do diretório do próprio script (independente do cwd do PM2)
require('dotenv').config({ path: require('path').join(__dirname, '.env') });
const { Client, LocalAuth, MessageMedia } = require('whatsapp-web.js');
const { createClient }      = require('@supabase/supabase-js');
const QRCode                = require('qrcode');
const path                  = require('path');
const fs                    = require('fs');
const { spawnSync }         = require('child_process');

// Mata Chrome Puppeteer órfão e remove lockfiles — necessário após crashes do PM2 no Windows
function limparLockChrome() {
  // Encerra processos Chrome que referenciam a sessão do wwebjs (via PowerShell — wmic removido no Win11)
  try {
    const r = spawnSync('powershell', [
      '-NonInteractive', '-NoProfile', '-Command',
      "Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'chrome.exe' -and $_.CommandLine -like '*wwebjs_auth*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
    ], { timeout: 10000 });
    if (r.status === 0) {
      console.log('[WhatsApp] Chrome Puppeteer anterior encerrado');
      // Aguarda Chrome liberar os handles do sistema de arquivos (2s)
      spawnSync('ping', ['-n', '1', '-w', '2000', '127.0.0.1'], { stdio: 'ignore' });
    }
  } catch { /* ignora */ }

  // Remove arquivos de lock com retry (Chrome pode demorar a liberar)
  const sessionDir = path.join(__dirname, '.wwebjs_auth', 'session');
  ['lockfile', 'SingletonLock', 'SingletonSocket', 'SingletonCookie'].forEach(f => {
    const p = path.join(sessionDir, f);
    for (let i = 0; i < 6 && fs.existsSync(p); i++) {
      try { fs.unlinkSync(p); console.log(`[WhatsApp] Lock removido: ${f}`); break; }
      catch { spawnSync('ping', ['-n', '1', '-w', '500', '127.0.0.1'], { stdio: 'ignore' }); }
    }
  });
}

if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
  console.error('[WhatsApp] SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY são obrigatórios no .env');
  process.exit(1);
}

const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

// ── Utilitários ──────────────────────────────────────────────────────

function normalizarFone(tel) {
  return String(tel || '').replace(/\D/g, '');
}

function foneBate(armazenado, recebido) {
  if (!armazenado || !recebido) return false;
  return armazenado === recebido ||
    recebido.endsWith(armazenado) ||
    armazenado.endsWith(recebido);
}

async function buscarRevenda(phone) {
  const limpo = normalizarFone(phone);
  const { data, error } = await sb.from('revendas').select('id, nome, tel, tel2, tel3');
  if (error) throw error;
  return (data || []).find(r =>
    [r.tel, r.tel2, r.tel3].some(t => foneBate(normalizarFone(t), limpo))
  );
}

// ── Persistência ─────────────────────────────────────────────────────

async function salvarMensagem(revendaId, direction, body, phone, mediaBase64, mediaMimetype, mediaFilename, contactName) {
  const { error } = await sb.from('whatsapp_messages').insert({
    revenda_id:     revendaId,
    direction,
    body:           body || '',
    phone:          phone || null,
    media_base64:   mediaBase64   || null,
    media_mimetype: mediaMimetype || null,
    media_filename: mediaFilename || null,
    contact_name:   contactName   || null,
  });
  if (error) console.error('[WhatsApp] Erro ao salvar msg:', error.message);
}

async function registrarHistorico(revendaId, tipo, descricao) {
  const { error } = await sb.from('historico_cards').insert({
    revenda_id:   revendaId,
    tipo,
    descricao,
    manual:       false,
    usuario_nome: 'WhatsApp Bot',
  });
  if (error) console.error('[WhatsApp] Erro ao salvar histórico:', error.message);
}

async function atualizarStatus(status, extra = {}) {
  const { error } = await sb.from('whatsapp_status').upsert(
    { id: 1, status, updated_at: new Date().toISOString(), ...extra },
    { onConflict: 'id' }
  );
  if (error) console.error('[WhatsApp] Erro ao atualizar status:', error.message);
}

// ── Resolução de contato (nome + número limpo) ───────────────────────
async function getContactInfo(msg) {
  const remoteJid = msg.fromMe ? msg.to : msg.from;
  const isGroup   = remoteJid.includes('@g.us');
  let name   = null;
  let number = null;

  if (!isGroup) {
    try {
      const contact = await msg.getContact();
      // Prioridade: agenda local > nome curto > pushname > nome verificado (business)
      name   = contact.name || contact.shortName || contact.pushname || contact.verifiedName || null;
      number = contact.number || null;
    } catch { /* fallback abaixo */ }

    // Se getContact() não retornou número, extrai do JID quando for dígitos reais
    if (!number) {
      const raw = remoteJid.replace(/@c\.us$/, '').replace(/@lid$/, '');
      number = /^\d{8,15}$/.test(raw) ? raw : null;
    }
    if (!name) name = number || remoteJid;
  }

  return { name, number, isGroup };
}

// ── Envio de mensagens pendentes ──────────────────────────────────────

const _processando = new Set(); // evita duplo envio (Realtime + polling simultâneos)

async function enviarPendente(msg) {
  if (_processando.has(msg.id)) return; // já está sendo processada
  if (!_clientReady) return;

  if (!msg.phone) {
    console.warn(`[WhatsApp] Mensagem ${msg.id} sem phone — marcando como erro`);
    await sb.from('mensagens_pendentes').update({ status: 'error' }).eq('id', msg.id);
    return;
  }

  _processando.add(msg.id);

  // Resolve chatId limpo em @c.us — @lid é resolvido via getContactById antes de enviar
  let chatId;
  if (msg.phone.includes('@lid')) {
    try {
      const contact = await client.getContactById(msg.phone);
      const num = contact?.number;
      if (num) {
        chatId = `${num.startsWith('55') ? num : '55' + num}@c.us`;
        console.log(`[WhatsApp] @lid resolvido → ${chatId}`);
      }
    } catch { /* fallback: usa @lid diretamente */ }
  }
  if (!chatId) {
    const dig = msg.phone.replace(/\D/g, '');
    chatId = msg.phone.includes('@')
      ? msg.phone
      : `${dig.startsWith('55') ? dig : '55' + dig}@c.us`;
  }

  console.log(`[WhatsApp] → Enviando: ${chatId} | ${(msg.body||'').slice(0,60)}`);

  // Prepara conteúdo: mídia ou texto
  let conteudo = msg.body || '';
  let sendOpts = {};
  if (msg.media_base64 && msg.media_mimetype) {
    conteudo = new MessageMedia(msg.media_mimetype, msg.media_base64, msg.media_filename || 'arquivo');
    if (msg.media_as_sticker) {
      sendOpts.sendMediaAsSticker = true;
    } else if (msg.body) {
      sendOpts.caption = msg.body;
    }
    console.log(`[WhatsApp] → ${msg.media_as_sticker ? 'Figurinha' : 'Mídia'}: ${msg.media_mimetype} (${msg.media_filename || 'sem nome'})`);
  }

  try {
    await client.sendMessage(chatId, conteudo, sendOpts);
    await sb.from('mensagens_pendentes').update({ status: 'sent' }).eq('id', msg.id);
    console.log(`[WhatsApp] ✓ ${chatId}`);
  } catch (err) {
    console.error(`[WhatsApp] ✗ (${chatId}): ${err.message}`);
    await sb.from('mensagens_pendentes').update({ status: 'error' }).eq('id', msg.id);
  } finally {
    _processando.delete(msg.id);
  }
}

async function processarPendentes() {
  const { data } = await sb.from('mensagens_pendentes')
    .select('*').eq('status', 'pending').order('created_at');
  for (const msg of data || []) {
    await enviarPendente(msg);
  }
}

// ── Cliente WhatsApp ─────────────────────────────────────────────────

const client = new Client({
  authStrategy: new LocalAuth({ dataPath: './.wwebjs_auth' }),
  webVersion: '2.3000.1023204675',
  webVersionCache: {
    type: 'remote',
    remotePath: 'https://raw.githubusercontent.com/wppconnect-team/wa-version/main/html/2.3000.1023204675.html',
  },
  puppeteer: {
    headless: true,
    protocolTimeout: 60000,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-accelerated-2d-canvas',
      '--no-first-run',
      '--no-zygote',
      '--disable-gpu',
      '--disable-extensions',
      '--disable-component-update',
    ],
  },
});

client.on('auth_failure', async msg => {
  console.error('[WhatsApp] Falha de autenticação — sessão inválida, gerando novo QR:', msg);
  _clientReady = false;
  await atualizarStatus('aguardando_qr', { qr_code: null, numero: null });
});

client.on('qr', async qr => {
  console.log('[WhatsApp] QR gerado — acesse Integrações no portal para escanear.');
  try {
    const qrDataUrl = await QRCode.toDataURL(qr, { width: 256, margin: 2 });
    await atualizarStatus('aguardando_qr', { qr_code: qrDataUrl, numero: null });
  } catch (err) {
    console.error('[WhatsApp] Erro ao salvar QR:', err.message);
  }
});

client.on('ready', async () => {
  _clientReady    = true;
  _isInitializing = false;
  const numero = client.info?.wid?.user || '';
  console.log(`[WhatsApp] Conectado. Número: ${numero || '(não disponível)'}`);
  await atualizarStatus('conectado', { qr_code: null, numero });

  // Envia mensagens que ficaram na fila durante offline
  await processarPendentes();

  // Monitora novas mensagens pendentes em tempo real
  sb.channel('pendentes-ch')
    .on('postgres_changes',
      { event: 'INSERT', schema: 'public', table: 'mensagens_pendentes' },
      async (payload) => {
        console.log(`[WhatsApp] Realtime INSERT mensagens_pendentes: phone=${payload.new?.phone}`);
        if (payload.new?.status !== 'pending') return;
        await enviarPendente(payload.new);
      }
    ).subscribe((status) => {
      console.log(`[WhatsApp] Canal pendentes-ch: ${status}`);
    });

  // Polling de segurança a cada 30s — só processa mensagens com >5s sem resposta
  setInterval(async () => {
    if (!_clientReady) return;
    const cutoff = new Date(Date.now() - 5000).toISOString();
    const { data } = await sb.from('mensagens_pendentes')
      .select('*').eq('status', 'pending')
      .lt('created_at', cutoff)
      .order('created_at').limit(10);
    const pendentes = (data || []).filter(m => !_processando.has(m.id));
    if (pendentes.length) {
      console.log(`[WhatsApp] Polling: ${pendentes.length} pendente(s) sem resposta do Realtime`);
      for (const msg of pendentes) await enviarPendente(msg);
    }
  }, 30000);
});

client.on('disconnected', async reason => {
  _clientReady    = false;
  _isInitializing = false;
  console.warn('[WhatsApp] Desconectado:', reason);
  await atualizarStatus('desconectado', { qr_code: null, numero: null });
});

// ── Eventos de mensagem ───────────────────────────────────────────────

client.on('message', async msg => {
  if (msg.isStatus || msg.from === 'status@broadcast') return;

  const { name: contactName, number, isGroup } = await getContactInfo(msg);
  const phone = number || msg.from.replace(/@c\.us$/, '').replace(/@lid$/, '');

  try {
    let mediaBase64 = null, mediaMimetype = null, mediaFilename = null;
    if (msg.hasMedia) {
      try {
        const media = await msg.downloadMedia();
        mediaBase64   = media.data;
        mediaMimetype = media.mimetype;
        mediaFilename = media.filename || null;
      } catch (me) {
        console.warn(`[WhatsApp] Não foi possível baixar mídia de ${phone}:`, me.message);
      }
    }
    const body = msg.body || (mediaFilename ? `[${mediaFilename}]` : (mediaMimetype ? '[mídia]' : ''));
    const rev  = isGroup ? null : await buscarRevenda(phone);
    await salvarMensagem(rev?.id || null, 'inbound', body, phone, mediaBase64, mediaMimetype, mediaFilename, contactName);
    if (rev) await registrarHistorico(rev.id, '💬 WhatsApp', body);
    console.log(`[WhatsApp] ← ${contactName || rev?.nome || phone}: ${body.slice(0, 80)}`);
  } catch (err) {
    console.error(`[WhatsApp] Erro (recebido de ${phone}):`, err.message);
  }
});

client.on('message_create', async msg => {
  if (!msg.fromMe) return;
  if (msg.isStatus || msg.to === 'status@broadcast') return;

  const { name: contactName, number, isGroup } = await getContactInfo(msg);
  const phone = number || msg.to.replace(/@c\.us$/, '').replace(/@lid$/, '');

  try {
    let mediaBase64 = null, mediaMimetype = null, mediaFilename = null;
    if (msg.hasMedia) {
      try {
        const media = await msg.downloadMedia();
        mediaBase64   = media.data;
        mediaMimetype = media.mimetype;
        mediaFilename = media.filename || null;
      } catch (me) {
        console.warn(`[WhatsApp] Não foi possível baixar mídia enviada para ${phone}:`, me.message);
      }
    }
    const body = msg.body || (mediaFilename ? `[${mediaFilename}]` : (mediaMimetype ? '[mídia]' : ''));
    const rev  = isGroup ? null : await buscarRevenda(phone);
    await salvarMensagem(rev?.id || null, 'outbound', body, phone, mediaBase64, mediaMimetype, mediaFilename, contactName);
    if (rev) await registrarHistorico(rev.id, '📤 WhatsApp enviado', body);
    console.log(`[WhatsApp] → ${contactName || rev?.nome || phone}: ${body.slice(0, 80)}`);
  } catch (err) {
    console.error(`[WhatsApp] Erro (enviado para ${phone}):`, err.message);
  }
});

// ── Comandos do portal (disconnect / reconnect) ───────────────────────
let _clientReady     = false;
let _isInitializing  = false; // impede dupla inicialização simultânea

sb.channel('commands-ch')
  .on('postgres_changes',
    { event: 'INSERT', schema: 'public', table: 'whatsapp_commands' },
    async (payload) => {
      const { id, action } = payload.new || {};
      if(!id) return;
      await sb.from('whatsapp_commands').update({ executed_at: new Date().toISOString() }).eq('id', id);

      if(action === 'disconnect'){
        console.log('[WhatsApp] Desconexão solicitada pelo portal');
        try { await client.logout(); } catch(e) { console.error('[WhatsApp] Erro ao desconectar:', e.message); }
        _clientReady    = false;
        _isInitializing = false;
        await atualizarStatus('iniciando', { qr_code: null, numero: null });
        setTimeout(() => { limparLockChrome(); _inicializar(); }, 2000);

      } else if(action === 'reconnect'){
        if(_clientReady){
          console.log('[WhatsApp] Já conectado, ignorando reconexão');
          await atualizarStatus('conectado', { qr_code: null, numero: client.info?.wid?.user || '' });
          return;
        }
        if(_isInitializing){
          console.log('[WhatsApp] Já inicializando (aguardando QR), ignorando reconexão duplicada');
          return;
        }
        console.log('[WhatsApp] Reconexão solicitada pelo portal');
        await atualizarStatus('iniciando', { qr_code: null, numero: null });
        limparLockChrome();
        setTimeout(() => _inicializar(), 500);
      }
    }
  ).subscribe();

// Encerramento limpo: fecha Chrome e marca desconectado ao parar o PM2
async function _encerrar() {
  try { await client.destroy(); } catch {}
  await atualizarStatus('desconectado', { qr_code: null, numero: null }).catch(() => {});
  process.exit(0);
}
process.on('SIGINT',  _encerrar);
process.on('SIGTERM', _encerrar);

function _inicializar() {
  if(_isInitializing || _clientReady) return;
  _isInitializing = true;
  client.initialize().catch(err => {
    console.error('[WhatsApp] Erro ao inicializar:', err.message);
    _isInitializing = false;
    atualizarStatus('desconectado', { qr_code: null, numero: null }).catch(() => {});
  });
}

limparLockChrome();
atualizarStatus('iniciando').catch(() => {});
_inicializar();
