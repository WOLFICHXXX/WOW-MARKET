const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("wolfMarket", {
  build: 1,
  getSettings: () => ipcRenderer.invoke("get-settings"),
  setSettings: (patch) => ipcRenderer.invoke("set-settings", patch),
  status: () => ipcRenderer.invoke("status"),
  log: () => ipcRenderer.invoke("log"),
  scanNow: () => ipcRenderer.invoke("scan-now"),
  readScans: () => ipcRenderer.invoke("read-scans"),
  installAddon: () => ipcRenderer.invoke("install-addon"),
  addonInfo: () => ipcRenderer.invoke("addon-info"),
  appUpdate: () => ipcRenderer.invoke("app-update"),
  findWow: () => ipcRenderer.invoke("find-wow"),
  pickWow: () => ipcRenderer.invoke("pick-wow"),
  notify: (title, body) => ipcRenderer.invoke("notify", title, body),
  openData: () => ipcRenderer.invoke("open-data"),
  version: () => ipcRenderer.invoke("app-version"),
  on: (ev, fn) => { if (["log", "status", "data-updated", "scans-changed"].includes(ev)) ipcRenderer.on(ev, (_, a) => fn(a)); },
});
