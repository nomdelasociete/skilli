"""Per call: the words to expect, as skil.li would have them at Stop.
vocab.txt: the event's attendees, then the user's contacts (a fixed
shuffle: the order a contact list has, unrelated to the call), 100 at most
(Apple's advice, DictationVocabulary's cap). prompt.txt: the same names in
one sentence for whisper, as many as fit its prompt (~450 characters)."""
import json, random, sys
from pathlib import Path
calls = Path(sys.argv[1])
contacts = json.load(open(calls / "contacts.json", encoding="utf-8"))
for d in sorted(p for p in calls.iterdir() if (p / "truth.json").exists()):
    t = json.load(open(d / "truth.json", encoding="utf-8"))
    rest = [c for c in contacts if c not in t["attendees"]]
    random.Random(7).shuffle(rest)
    vocab = (t["attendees"] + rest)[:100]
    (d / "vocab.txt").write_text("\n".join(vocab) + "\n", encoding="utf-8")
    head, also = ("Participants : ", " Aussi : ") if t["language"] == "fr" else ("Attendees: ", " Also: ")
    prompt = head + ", ".join(t["attendees"]) + "."
    extra = []
    for c in rest:
        candidate = prompt + also + ", ".join(extra + [c]) + "."
        if len(candidate) > 450:
            break
        extra.append(c)
    prompt = prompt + (also + ", ".join(extra) + "." if extra else "")
    (d / "prompt.txt").write_text(prompt, encoding="utf-8")
    named = set(t["names"]) - set(t["attendees"])
    print(d.name, len(vocab), "vocab;", "prompt", len(prompt), "chars,", len(t["attendees"]) + len(extra), "names,",
          f"{len(named & set(extra))}/{len(named)} mentioned names in prompt, {len(named & set(vocab))}/{len(named)} in vocab")
