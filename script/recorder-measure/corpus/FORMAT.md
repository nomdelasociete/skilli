# Meeting scripts for a speech-engine measurement

These scripts are read aloud by text-to-speech voices, mixed into recorded
"calls", and transcribed by speech engines. The script text is the ground
truth the transcripts are scored against (errors per hundred words, names
spelled right). Everything is invented: invented people, invented companies,
no real person, no real company except the invented ones listed.

## File

One JSON file per call, `<id>.json`, UTF-8, pretty-printed:

```json
{
  "id": "en03",
  "language": "en",
  "title": "Incident review: checkout outage",
  "attendees": [
    {"id": "me", "name": "Camille Rocher"},
    {"id": "a",  "name": "Priyanka Venkataraman"},
    {"id": "b",  "name": "Bartholomew Okonkwo"}
  ],
  "mentioned": ["Ingrid Haugland", "Nimbus", "Quillfeather"],
  "turns": [
    {"speaker": "a", "text": "Okay, I think everyone's here. Camille, do you want to start?"},
    {"speaker": "me", "text": "Sure. So on Tuesday night the checkout went down for about forty minutes."},
    {"speaker": "b", "text": "Forty-two, actually.", "overlap": true}
  ]
}
```

- `attendees`: the people in the call, `me` first (the person recording).
  Use exactly the cast given in your brief.
- `mentioned`: every person and company named in the talk who is not an
  attendee (people the attendees talk about, clients, suppliers). Use the
  names given in your brief; you may add a few more invented ones.
- `turns`: who speaks and exactly what they say, in order.
- `"overlap": true` on a turn: it starts before the previous turn has
  finished (an interruption, someone talking over, a quick "yes" or "right"
  while the other person is still talking). About one turn in eight.
  Never on the first turn.

## Writing rules (they matter for scoring)

- Spoken language, as people really talk in a work call: contractions,
  short replies, people asking each other questions, agreeing, pushing back,
  a joke now and then, someone checking they can be heard, someone saying
  "sorry, go ahead" after talking over someone. Not a written report.
- Names often: each attendee is addressed or mentioned by name at least
  four times across the call (first name alone, full name, last name
  alone, "Ingrid's team"), and each mentioned name comes up at least twice.
  Names are the hard part we measure.
- Numbers ALWAYS in words: "forty-two", "three hundred thousand euros",
  "fifteen percent", "deux mille cinq cents", "quinze pour cent". No digits,
  no symbols (no %, €, $, &, /, @), no years, no decimals, no times like
  "14h30" (say "two thirty" / "quatorze heures trente"), no dates with digits.
- No abbreviations a voice would read letter by letter, unless meant to be
  read so and common ("CEO", "Q3" is NOT allowed: say "third quarter";
  "PDG", "RH", "CRM" are fine in French; "CEO", "HR", "API" fine in English).
- No stage directions, no brackets, no emojis, no markdown, no speaker
  names inside `text`.
- Fillers sparingly ("um", "uh", "euh", "bon", "ben", "you know"): at most
  one turn in ten.
- Turn length varies: many one-liners, some long explanations (up to about
  ninety words). Each call has a beginning (hello, can you hear me), a
  middle with a real discussion and at least one disagreement, decisions
  and action items with owners ("Kwabena, can you send the numbers to
  Ingrid by Friday?"), and an end.
- French scripts: natural French as spoken in a French company (vous or tu
  as the team would; "on" for "nous"), accents and apostrophes correct.

## Length

Given in your brief, in words of `text` (count them: `python3 -c` over the
file). Stay within ten percent.

## Check before you finish

Run, for each file:

```sh
python3 -c 'import json,sys,re
for p in sys.argv[1:]:
    d=json.load(open(p)); t=" ".join(x["text"] for x in d["turns"])
    assert d["turns"][0].get("overlap") is not True
    assert not re.search(r"[0-9%€$&/@\[\]()*_#]", t), re.findall(r".{20}[0-9%€$&/@\[\]()*_#].{20}", t)[:5]
    ids={a["id"] for a in d["attendees"]}; assert all(x["speaker"] in ids for x in d["turns"])
    print(p, len(t.split()), "words", len(d["turns"]), "turns", sum(1 for x in d["turns"] if x.get("overlap")), "overlaps")' *.json
```
