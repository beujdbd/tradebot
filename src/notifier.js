/** Notifications Telegram (optionnel). Ne bloque jamais le bot. */
export function createNotifier(config, fetchImpl = globalThis.fetch) {
  if (!config.telegram) return () => {};
  const { token, chatId } = config.telegram;
  return (text) =>
    fetchImpl(`https://api.telegram.org/bot${token}/sendMessage`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ chat_id: chatId, text, disable_web_page_preview: true }),
      signal: AbortSignal.timeout(8_000),
    }).catch(() => {});
}
