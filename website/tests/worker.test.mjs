import assert from "node:assert/strict";
import test from "node:test";
import { route } from "../worker.mjs";

const ORIGIN = "https://skil.li";
const CACHE = "public, max-age=0, must-revalidate";
const DOWNLOAD = "https://github.com/nomdelasociete/skilli/releases/latest/download/skil.li.dmg";
const APPCAST = "https://github.com/nomdelasociete/skilli/releases/latest/download/appcast.xml";

function ask(path) {
  return route(new Request(ORIGIN + path));
}

test("health is plain text ok", async () => {
  const response = ask("/health");
  assert.equal(response.status, 200);
  assert.equal(await response.text(), "ok");
  assert.equal(response.headers.get("content-type"), "text/plain; charset=utf-8");
  assert.equal(response.headers.get("cache-control"), CACHE);
});

test("download and appcast stay temporary redirects", () => {
  const download = ask("/download");
  const appcast = ask("/appcast.xml");
  assert.equal(download.status, 302);
  assert.equal(download.headers.get("location"), DOWNLOAD);
  assert.equal(appcast.status, 302);
  assert.equal(appcast.headers.get("location"), APPCAST);
  assert.equal(download.headers.get("cache-control"), CACHE);
  assert.equal(appcast.headers.get("cache-control"), CACHE);
});

test("old /website paths strip the prefix and keep the query", () => {
  const page = ask("/website/legal.html?x=1");
  assert.equal(page.status, 301);
  assert.equal(page.headers.get("location"), ORIGIN + "/legal.html?x=1");
  assert.equal(ask("/website").headers.get("location"), ORIGIN + "/");
  assert.equal(ask("/website/").headers.get("location"), ORIGIN + "/");
  assert.equal(
    ask("/website/skillies/files/week-number.sh").headers.get("location"),
    ORIGIN + "/skillies/files/week-number.sh",
  );
  assert.equal(
    ask("/website//attacker.example?x=1").headers.get("location"),
    ORIGIN + "//attacker.example?x=1",
  );
});

test("ordinary pages stay on the static site", () => {
  assert.equal(ask("/"), null);
  assert.equal(ask("/skillies/"), null);
  assert.equal(ask("/website-extra"), null);
});
