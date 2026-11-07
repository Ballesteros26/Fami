window.ndpWeb = {
  saveBase64(fileName, base64) {
    const raw = atob(base64);
    const data = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i++) data[i] = raw.charCodeAt(i);
    const url = URL.createObjectURL(new Blob([data], {type: 'application/octet-stream'}));
    const a = document.createElement('a');
    a.href = url; a.download = fileName; document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 2000);
  },
  scrollToId(id) {
    const element = document.getElementById(id);
    if (element) element.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }
};
