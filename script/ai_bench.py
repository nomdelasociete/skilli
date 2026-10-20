#!/usr/bin/env python3
"""Latency of the AI engines skil.li can drive on the user's subscriptions.

Measures, for each engine, a one-sentence spelling fix:
- "on demand": the CLI is started when the request is made;
- "spare": a process started and prepared ahead (what skil.li keeps ready),
  then used once and killed.

Reports time to first word, time to complete text, input tokens per request
and the spare's memory. Each run spends a few hundred to ~10k tokens of the
user's plan (see docs/ai-engines.md). Runs in an empty temporary directory and
without proxy variables, like skil.li will.

    script/ai_bench.py                      # claude + codex, 3 runs each
    script/ai_bench.py --engine grok --runs 1
    script/ai_bench.py --engine claude --model sonnet
"""
import argparse
import json
import os
import select
import statistics
import subprocess
import tempfile
import time

TEXTS = [
    "je sui allé au marcher hier",
    "les enfant on manger des pome",
    "elle a acheter trois livre",
]
SYSTEM = "Tu transformes le texte fourni selon l'instruction. Réponds uniquement avec le résultat, sans commentaire."
INSTRUCTION = "Instruction : corrige l'orthographe.\nTexte : "
TIMEOUT = 60

# Codex features that add tools (and tokens) a text transform never uses.
CODEX_LEAN = [
    "apps", "browser_use", "browser_use_external", "browser_use_full_cdp_access", "browser_annotation_api",
    "computer_use", "goals", "image_generation", "multi_agent", "plugins", "remote_plugin", "shell_tool",
    "skill_search", "sleep_tool", "tool_suggest", "unified_exec", "view_image", "hooks", "in_app_browser",
    "realtime_conversation",
]


def clean_env():
    drop = {"HTTPS_PROXY", "HTTP_PROXY", "ALL_PROXY", "NO_PROXY", "ANTHROPIC_BASE_URL"}
    return {k: v for k, v in os.environ.items() if k.upper() not in drop}


def rss_mb(pid):
    out = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
    return int(out) / 1024 if out else 0.0


class Process:
    """A line-delimited JSON process on stdin/stdout."""

    def __init__(self, args, cwd):
        self.p = subprocess.Popen(args, cwd=cwd, env=clean_env(), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL, text=True, bufsize=1)

    def write(self, obj):
        self.p.stdin.write(json.dumps(obj) + "\n")
        self.p.stdin.flush()

    def lines(self, timeout=TIMEOUT):
        end = time.time() + timeout
        while time.time() < end:
            ready, _, _ = select.select([self.p.stdout], [], [], 0.2)
            if not ready:
                continue
            line = self.p.stdout.readline()
            if not line:
                return
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue

    def kill(self):
        self.p.kill()
        self.p.wait()


class Claude(Process):
    """Unmodified `claude` binary, headless, stripped down to a text transform."""

    def __init__(self, cwd, model):
        super().__init__([
            "claude", "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
            "--include-partial-messages", "--no-session-persistence", "--model", model or "haiku",
            "--tools", "", "--setting-sources", "", "--strict-mcp-config", "--disable-slash-commands",
            "--system-prompt", SYSTEM,
        ], cwd)

    def prepare(self):
        pass  # ready to read stdin once spawned; ~0.5 s to connect

    def ask(self, text):
        t0 = time.time()
        self.write({"type": "user", "message": {"role": "user", "content": INSTRUCTION + text}})
        first, out, tokens = None, "", None
        for e in self.lines():
            if e.get("type") != "stream_event":
                continue
            ev = e["event"]
            if ev.get("type") == "message_start":
                u = ev["message"].get("usage", {})
                tokens = sum(u.get(k) or 0 for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
            elif ev.get("type") == "content_block_delta" and ev["delta"].get("type") == "text_delta":
                first = first or time.time() - t0
                out += ev["delta"]["text"]
            elif ev.get("type") == "message_stop":
                # Claude Code then writes a post-turn summary (~1.6 s); never wait for `result`.
                return first, time.time() - t0, out.strip(), tokens
        return None, None, "timeout", None


class Codex(Process):
    """`codex app-server` (JSON-RPC, experimental) on the ChatGPT plan."""

    def __init__(self, cwd, model):
        args = ["codex", "app-server", "-c", 'web_search="disabled"']
        for feature in CODEX_LEAN:
            args += ["--disable", feature]
        super().__init__(args, cwd)
        self.cwd, self.model, self.n = cwd, model or "gpt-6-luna", 0

    def send(self, method, params=None, notify=False):
        msg = {"method": method}
        if params is not None:
            msg["params"] = params
        if not notify:
            self.n += 1
            msg["id"] = self.n
        self.write(msg)
        return msg.get("id")

    def call(self, method, params):
        i = self.send(method, params)
        for o in self.lines():
            if o.get("id") == i:
                if "error" in o:
                    raise RuntimeError(f"{method}: {o['error']}")
                return o["result"]
        raise RuntimeError(f"{method}: no answer in {TIMEOUT} s")

    def prepare(self):
        self.call("initialize", {"clientInfo": {"name": "skilli-bench", "version": "0.0.1"}})
        self.send("initialized", notify=True)
        self.thread = self.call("thread/start", {
            "cwd": self.cwd, "model": self.model, "ephemeral": True, "baseInstructions": SYSTEM,
            "sandbox": "read-only", "approvalPolicy": "never",
        })["thread"]["id"]

    def ask(self, text):
        t0 = time.time()
        self.send("turn/start", {"threadId": self.thread, "effort": "low",
                                 "input": [{"type": "text", "text": INSTRUCTION + text}]})
        first, out, tokens = None, "", None
        for o in self.lines():
            m = o.get("method")
            if m == "item/agentMessage/delta":
                first = first or time.time() - t0
                out += o["params"].get("delta", "")
            elif m == "thread/tokenUsage/updated":
                tokens = o["params"]["tokenUsage"]["last"]["inputTokens"]
            elif m == "turn/completed":
                return first, time.time() - t0, out.strip(), tokens
            elif m == "error":
                return None, None, json.dumps(o["params"])[:200], None
        return None, None, "timeout", None


class Grok(Process):
    """`grok agent stdio` (ACP) on the SuperGrok plan."""

    def __init__(self, cwd, model):
        super().__init__(["grok", "agent", "-m", model or "grok-4.5", "--reasoning-effort", "low", "--no-leader", "stdio"], cwd)
        self.cwd, self.n = cwd, 0

    def send(self, method, params):
        self.n += 1
        self.write({"jsonrpc": "2.0", "id": self.n, "method": method, "params": params})
        return self.n

    def events(self):
        for o in self.lines():
            if "method" in o and "id" in o:  # agent asks the client: refuse
                if o["method"] == "session/request_permission":
                    self.write({"jsonrpc": "2.0", "id": o["id"], "result": {"outcome": {"outcome": "cancelled"}}})
                else:
                    self.write({"jsonrpc": "2.0", "id": o["id"], "error": {"code": -32601, "message": "not supported"}})
                continue
            yield o

    def call(self, method, params):
        i = self.send(method, params)
        for o in self.events():
            if o.get("id") == i:
                if "error" in o:
                    raise RuntimeError(f"{method}: {o['error']}")
                return o["result"]
        raise RuntimeError(f"{method}: no answer in {TIMEOUT} s")

    def prepare(self):
        self.call("initialize", {"protocolVersion": 1, "clientCapabilities": {
            "fs": {"readTextFile": False, "writeTextFile": False}, "terminal": False}})
        self.session = self.call("session/new", {"cwd": self.cwd, "mcpServers": []})["sessionId"]

    def ask(self, text):
        t0 = time.time()
        i = self.send("session/prompt", {"sessionId": self.session, "prompt": [
            {"type": "text", "text": SYSTEM + "\n" + INSTRUCTION + text}]})
        first, out = None, ""
        for o in self.events():
            if o.get("method") == "session/update":
                u = o["params"]["update"]
                if u.get("sessionUpdate") == "agent_message_chunk":
                    first = first or time.time() - t0
                    out += u.get("content", {}).get("text", "")
            elif o.get("id") == i:
                return first, time.time() - t0, out.strip(), None  # ACP reports no token usage
        return None, None, "timeout", None


ENGINES = {"claude": Claude, "codex": Codex, "grok": Grok}


def run(engine, model, runs, cwd):
    cls = ENGINES[engine]
    rows = {"on demand": [], "spare": []}
    memory = 0.0
    for mode in rows:
        for text in (TEXTS * runs)[:runs]:
            t0 = time.time()
            proc = cls(cwd, model)
            try:
                proc.prepare()
                setup = time.time() - t0
                if mode == "spare":
                    time.sleep(1.0)  # ready ~0.5 s after spawn; give it its head start
                    setup = 0.0
                    memory = rss_mb(proc.p.pid)
                first, done, out, tokens = proc.ask(text)
            except RuntimeError as error:
                first, done, out, tokens = None, None, str(error)[:200], None
            finally:
                proc.kill()
            rows[mode].append((first and first + setup, done and done + setup, out, tokens))
    for mode, results in rows.items():
        ok = [r for r in results if r[0] is not None]
        if not ok:
            print(f"| {engine} {model or ''} | {mode} | failed: {results[0][2]} | | | |")
            continue
        tokens = next((r[3] for r in ok if r[3]), None)
        print(f"| {engine} {model or ''} | {mode} | {statistics.median(r[0] for r in ok):.2f} s "
              f"| {statistics.median(r[1] for r in ok):.2f} s | {tokens or '—'} "
              f"| {f'{memory:.0f} MB' if mode == 'spare' else ''} |"
              + (f" {len(results) - len(ok)} failed" if len(ok) < len(results) else ""))
        print(f"|   ↳ | | “{ok[0][2]}” | | | |")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--engine", choices=[*ENGINES, "all"], default=None,
                        help="engine to measure (default: claude and codex; grok is slow on its plan)")
    parser.add_argument("--model", help="model id for the engine (defaults: haiku, gpt-6-luna, grok-4.5)")
    parser.add_argument("--runs", type=int, default=3)
    args = parser.parse_args()
    engines = ["claude", "codex"] if args.engine is None else list(ENGINES) if args.engine == "all" else [args.engine]
    cwd = tempfile.mkdtemp(prefix="skilli-ai-bench-")
    print("| Engine | Mode | First word | Complete | Input tokens | Spare memory |")
    print("|---|---|---|---|---|---|")
    for engine in engines:
        run(engine, args.model, args.runs, cwd)


if __name__ == "__main__":
    main()
