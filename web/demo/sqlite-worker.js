import sqlite3InitModule from "@sqlite.org/sqlite-wasm";

let database;

const initialize = async () => {
  const sqlite3 = await sqlite3InitModule();
  if (!sqlite3.oo1.OpfsDb) {
    throw new Error("This browser does not provide SQLite OPFS storage");
  }
  database = new sqlite3.oo1.OpfsDb("/ocaml-demo.sqlite");
  database.exec(
    "create table if not exists kvs (address text primary key not null, payload text not null)",
  );
  const entries = [];
  database.exec({
    sql: "select address, payload from kvs order by address",
    rowMode: "array",
    callback: (row) => entries.push(row),
  });
  return entries;
};

const store = (entries) => {
  database.exec("begin immediate transaction");
  try {
    for (const [address, payload] of entries) {
      database.exec({
        sql: "insert or replace into kvs (address, payload) values (?, ?)",
        bind: [address, payload],
      });
    }
    database.exec("commit");
  } catch (error) {
    database.exec("rollback");
    throw error;
  }
};

const remove = (addresses) => {
  database.exec("begin immediate transaction");
  try {
    for (const address of addresses) {
      database.exec({
        sql: "delete from kvs where address = ?",
        bind: [address],
      });
    }
    database.exec("commit");
  } catch (error) {
    database.exec("rollback");
    throw error;
  }
};

self.onmessage = async ({ data }) => {
  try {
    let result = null;
    if (data.type === "initialize") result = await initialize();
    else if (data.type === "store") store(data.entries);
    else if (data.type === "delete") remove(data.addresses);
    else throw new Error(`Unknown SQLite worker request: ${data.type}`);
    self.postMessage({ id: data.id, result });
  } catch (error) {
    self.postMessage({ id: data.id, error: String(error) });
  }
};
