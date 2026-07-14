require('dotenv').config();
const { Client, LocalAuth } = require('whatsapp-web.js');
const { createClient }      = require('@supabase/supabase-js');
const QRCode                = require('qrcode');

if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
  console.error('[WhatsApp] SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY são obrigatórios no .env');
  process.exit(1);
}

const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

function normalizarFone(tel) {
  return String(tel || '').replace(/\D/g, '');
}

// Tolerante a prefixo +55: "11999..." bate com "5511999..."
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

async function registrar(revendaId, tipo, descricao) {
  const { error } = await sb.from('historico_cards').insert({
    revenda_id:   revendaId,
    tipo,
    descricao,
    manual:       false,
    usuario_nome: 'WhatsApp Bot',
  });
  if (error) throw error;
}

async function atualizarStatus(status, extra = {}) {
  const { error } = await sb.from('whatsapp_status').upsert(
    { id: 1, status, updated_at: new Date().toISOString(), ...extra },
    { onConflict: 'id' }
  );
  if (error) console.error('[WhatsApp] Erro ao atualizar status:', error.message);
}

const client = new Client({
  authStrategy: new LocalAuth({ dataPath: './.wwebjs_auth' }),
  puppeteer: { headless: true, args: ['--no-sandbox', '--disable-setuid-sandbox'] },
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
  const numero = client.info?.wid?.user || '';
  console.log(`[WhatsApp] Conectado. Número: ${numero || '(não disponível)'}`);
  await atualizarStatus('conectado', { qr_code: null, numero });
});

client.on('disconnected', async reason => {
  console.warn('[WhatsApp] Desconectado:', reason);
  await atualizarStatus('desconectado', { qr_code: null, numero: null });
});

client.on('message', async msg => {
  const phone = msg.from.replace('@c.us', '');
  try {
    const rev = await buscarRevenda(phone);
    if (!rev) return;
    await registrar(rev.id, '💬 WhatsApp', msg.body);
    console.log(`[WhatsApp] ← ${rev.nome}: ${msg.body.slice(0, 80)}`);
  } catch (err) {
    console.error(`[WhatsApp] Erro (recebido de ${phone}):`, err.message);
  }
});

client.on('message_create', async msg => {
  if (!msg.fromMe) return;
  const phone = msg.to.replace('@c.us', '');
  try {
    const rev = await buscarRevenda(phone);
    if (!rev) return;
    await registrar(rev.id, '📤 WhatsApp enviado', msg.body);
    console.log(`[WhatsApp] → ${rev.nome}: ${msg.body.slice(0, 80)}`);
  } catch (err) {
    console.error(`[WhatsApp] Erro (enviado para ${phone}):`, err.message);
  }
});

atualizarStatus('iniciando').catch(() => {});
client.initialize();
