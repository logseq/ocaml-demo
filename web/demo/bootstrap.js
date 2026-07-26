const isNative = Boolean(window.webkit?.messageHandlers?.native);

if (!isNative) {
  const worker = new Worker(new URL("./sqlite-worker.js", import.meta.url), {
    type: "module",
  });
  let nextRequestId = 1;
  const pending = new Map();

  worker.onmessage = ({ data }) => {
    const request = pending.get(data.id);
    if (!request) return;
    pending.delete(data.id);
    if (data.error) request.reject(new Error(data.error));
    else request.resolve(data.result);
  };

  const request = (type, payload = {}) =>
    new Promise((resolve, reject) => {
      const id = nextRequestId++;
      pending.set(id, { resolve, reject });
      worker.postMessage({ id, type, ...payload });
    });

  const entries = await request("initialize");
  const cache = new Map(entries);

  window.ocamlDemoSQLiteRestore = (address) => cache.get(address);
  window.ocamlDemoSQLiteList = () => Array.from(cache.keys());
  window.ocamlDemoSQLiteStore = (addresses, payloads) => {
    const entries = addresses.map((address, index) => [
      address,
      payloads[index],
    ]);
    for (const [address, payload] of entries) cache.set(address, payload);
    void request("store", { entries });
  };
  window.ocamlDemoSQLiteDelete = (addresses) => {
    for (const address of addresses) cache.delete(address);
    void request("delete", { addresses });
  };
}

await import("./dist/web/demo/main.js");
