// Public share URLs store plain MML server-side; no login and no execution.
(() => {
  window.ndpShare = {
    async create(mml) {
      // Keep the original MML untouched on the server while avoiding WAF false positives
      // caused by comment syntax such as /* ... */ in the POST body.
      const bytes = new TextEncoder().encode(String(mml));
      if (bytes.length === 0 || bytes.length > 65536) {
        throw new Error('MMLは1～65536バイトで指定してください。');
      }
      let binary = '';
      for (let i = 0; i < bytes.length; i += 8192) {
        binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
      }
      const encodedMml = 'NDP64:' + btoa(binary);
      const response = await fetch(new URL('api/share.php', document.baseURI), {
        method: 'POST',
        credentials: 'same-origin',
        headers: { 'Content-Type': 'text/plain; charset=utf-8', 'X-NDP-Share': '1' },
        body: encodedMml
      });
      const raw = await response.text();
      let json = {};
      try { json = JSON.parse(raw); } catch (_) { /* A WAF may return an HTML error page. */ }
      if (!response.ok) {
        const serverMessage = typeof json.error === 'string' ? json.error : '';
        const hint = response.status === 403 && !serverMessage
          ? '（サーバー設定・WAFによる拒否の可能性があります）' : '';
        throw new Error(serverMessage || `HTTP ${response.status}${hint}`);
      }
      if (!/^[A-Za-z0-9_-]{16}$/.test(json.id || '')) throw new Error('サーバーの応答が正しくありません。');
      return new URL(`api/card.php?id=${encodeURIComponent(json.id)}`, document.baseURI).href;
    },
    tweet(url, title) {
      if (!url) return;
      const name = title && title.trim() ? title.trim() : 'NDP Online';
      const text = `#MSXNDP #MSX\n${name}\n${url}`;
      const params = new URLSearchParams({ text });
      window.open('https://x.com/intent/tweet?' + params.toString(), '_blank', 'noopener,noreferrer');
    },
    async copy(url) {
      if (!url) return;
      if (navigator.clipboard?.writeText) await navigator.clipboard.writeText(url);
      else { const input = document.getElementById('ndp-share-url'); input?.select(); document.execCommand('copy'); }
    }
  };
})();
