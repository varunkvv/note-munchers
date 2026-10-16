#!/usr/bin/env python3
"""Makes and checks the Note Munchers voice clips with ElevenLabs.

lines.json (next to this file) is the bank: one entry per clip with its id, the
situation that says it (a NoteCore `Speech` case or an app line), the line number from
the line sheet, the note it names (or null) and the words. `say` overrides what is sent
to text-to-speech when the spelling needs help, `tag` is the eleven_v3 audio tag.

    python3 voicebank.py make  --masters DIR [--only id,id] [--redo id,id] [--max-used N]
    python3 voicebank.py check --masters DIR [--only id,id] [--cached]

make: for every clip missing from App/Resources/Voice it takes the raw mp3 from DIR (or
asks text-to-speech for one), trims the silence, evens out the loudness and writes
App/Resources/Voice/<id>.m4a. Clips that exist are skipped, so a rerun only makes what is
new or was deleted. --redo deletes those clips and their raw mp3s first (a retake).
Stops before the account's character count would pass --max-used.

check: sends every clip to speech-to-text (scribe_v1) and compares the transcript with
the line, letters included (the note's letter has to come back as a capital letter, so
"A" said as "uh" fails). Writes DIR/check.json and prints the clips that don't match.

The key is read from ~/.config/elevenlabs/api_key (or ELEVENLABS_API_KEY). It never goes
in the repo or the app. Needs ffmpeg and afconvert (macOS).
"""
import argparse, json, os, re, subprocess, sys, tempfile, time, urllib.error, urllib.request, uuid

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
CLIPS = os.path.join(REPO, "App", "Resources", "Voice")
API = "https://api.elevenlabs.io"
VOICE = "cgSgspJ2msm6clMCkdW9"  # jessica, an elevenlabs built-in voice
MODEL = "eleven_v3"


def key():
    k = os.environ.get("ELEVENLABS_API_KEY")
    if not k:
        with open(os.path.expanduser("~/.config/elevenlabs/api_key")) as f:
            k = f.read().strip()
    return k


def request(path, data=None, headers=None, timeout=180):
    h = {"xi-api-key": key()}
    h.update(headers or {})
    for attempt in range(4):
        req = urllib.request.Request(API + path, data=data, headers=h, method="POST" if data is not None else "GET")
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            body = e.read()[:300].decode(errors="replace")
            if e.code in (429, 500, 502, 503) and attempt < 3:
                time.sleep(3 * (attempt + 1))
                continue
            raise SystemExit(f"{path}: http {e.code} {body}")


def characters_used():
    sub = json.loads(request("/v1/user/subscription"))
    return sub["character_count"], sub["character_limit"]


def tts_text(clip):
    words = clip.get("say") or clip["text"]
    # sentence case reads more naturally than the line sheet's lowercase
    words = re.sub(r"(^|[.!?]\s+)([a-z])", lambda m: m.group(1) + m.group(2).upper(), words)
    return f"[{clip['tag']}] {words}" if clip.get("tag") else words


def tts(text):
    body = json.dumps({"text": text, "model_id": MODEL, "voice_settings": {"stability": 0.5}}).encode()
    return request(f"/v1/text-to-speech/{VOICE}?output_format=mp3_44100_128", body, {"Content-Type": "application/json"})


def process(mp3, out):
    """Trim silence (keep a little air at each end), even out loudness, mono AAC."""
    with tempfile.TemporaryDirectory() as tmp:
        trimmed = os.path.join(tmp, "t.wav")
        trim = ("silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.05,"
                "areverse,silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.15,areverse")
        run(["ffmpeg", "-v", "error", "-y", "-i", mp3, "-af", trim, "-ac", "1", "-ar", "44100", trimmed])
        # two-pass loudnorm, linear, so short clips aren't pumped
        log = run(["ffmpeg", "-hide_banner", "-i", trimmed, "-af", "loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json",
                   "-f", "null", "-"], stderr=True)
        m = json.loads(log[log.rindex("{"):log.rindex("}") + 1])
        norm = (f"loudnorm=I=-16:TP=-1.5:LRA=11:linear=true:measured_I={m['input_i']}:measured_TP={m['input_tp']}:"
                f"measured_LRA={m['input_lra']}:measured_thresh={m['input_thresh']}:offset={m['target_offset']}")
        level = os.path.join(tmp, "n.wav")
        run(["ffmpeg", "-v", "error", "-y", "-i", trimmed, "-af", norm, "-ar", "44100", level])
        run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "64000", level, out])


def run(cmd, stderr=False):
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        raise SystemExit(f"{cmd[0]} failed: {p.stderr[-500:]}")
    return p.stderr if stderr else p.stdout


def load(only):
    with open(os.path.join(HERE, "lines.json")) as f:
        clips = json.load(f)
    if only:
        want = set(only.split(","))
        clips = [c for c in clips if c["id"] in want]
        missing = want - {c["id"] for c in clips}
        if missing:
            raise SystemExit(f"not in lines.json: {sorted(missing)}")
    return clips


def make(args):
    os.makedirs(CLIPS, exist_ok=True)
    os.makedirs(args.masters, exist_ok=True)
    clips = load(args.only)
    for cid in (args.redo.split(",") if args.redo else []):
        for path in (os.path.join(CLIPS, cid + ".m4a"), os.path.join(args.masters, cid + ".mp3")):
            if os.path.exists(path):
                os.remove(path)
    used, limit = characters_used()
    print(f"characters used {used} of {limit}, stopping before {args.max_used}")
    spent = made = 0
    for clip in clips:
        out = os.path.join(CLIPS, clip["id"] + ".m4a")
        if os.path.exists(out):
            continue
        mp3 = os.path.join(args.masters, clip["id"] + ".mp3")
        if not os.path.exists(mp3):
            text = tts_text(clip)
            if used + len(text) > args.max_used:
                print(f"stop: {clip['id']} would take the count to {used + len(text)}")
                break
            audio = tts(text)
            with open(mp3, "wb") as f:
                f.write(audio)
            used += len(text)
            spent += len(text)
            made += 1
            print(f"made {clip['id']} ({len(text)} chars): {text}")
            if made % 10 == 0:
                # the account's count lags a little behind, and a retried request may have
                # been billed too. trust whichever is higher
                used = max(used, characters_used()[0])
        process(mp3, out)
    used, limit = characters_used()
    print(f"spent about {spent} characters, account now at {used} of {limit}")


# MARK: check

FILLERS = {"ooh": "oh", "oh": "oh", "ohh": "oh", "oooh": "oh", "ooo": "oh", "hmm": "hmm", "hm": "hmm",
           "mm": "hmm", "mmm": "hmm", "hmmm": "hmm", "oopsy": "oopsie", "oopsie": "oopsie", "okay": "ok",
           "yay": "yay", "yey": "yay", "2": "two", "1": "one"}


def tokens(text):
    """Words with their original case, punctuation stripped. F# and F-sharp become F sharp."""
    text = text.replace("’", "'").replace("F#", "F sharp").replace("f#", "F sharp")
    text = re.sub(r"\b([Ff])-sharp\b", r"\1 sharp", text)
    text = re.sub(r"\buh-oh\b", "uh oh", text, flags=re.I)
    text = re.sub(r"\bgrown-up\b", "grown up", text, flags=re.I)
    text = re.sub(r"\([^)]*\)|\[[^\]]*\]", " ", text)  # audio events like (laughs)
    out = []
    for w in re.split(r"[\s\-]+", text):
        w = re.sub(r"^[^\w']+|[^\w']+$", "", w)
        if w:
            out.append(w)
    return out


def norm(w):
    w = w.lower().replace("'", "")
    return FILLERS.get(w, w)


def letter_spots(clip, words):
    """Indexes in the line's words that are the note's letter."""
    if not clip.get("note"):
        if clip["situation"] in ("sharpHint", "almostMiddleC"):
            return [i for i, w in enumerate(words) if w in ("F", "C")]
        return []
    letter = clip["note"][0]
    return [i for i, w in enumerate(words) if w == letter]


def stt(path):
    boundary = uuid.uuid4().hex
    parts = []
    for name, value in (("model_id", "scribe_v1"), ("language_code", "en"), ("tag_audio_events", "true")):
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode())
    with open(path, "rb") as f:
        audio = f.read()
    parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="clip.m4a"\r\n'
                 f'Content-Type: audio/mp4\r\n\r\n'.encode() + audio + b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode())
    body = b"".join(parts)
    res = json.loads(request("/v1/speech-to-text", body, {"Content-Type": f"multipart/form-data; boundary={boundary}"}))
    events = [w["text"] for w in res.get("words", []) if w.get("type") == "audio_event"]
    return res.get("text", ""), events


def duration(path):
    out = run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path])
    return float(out.strip())


# speech-to-text writes some letters as the word that sounds the same. that's the letter
# said right. never for A: "a" is how "uh" comes back
HOMOPHONES = {"B": {"bee", "be"}, "C": {"see", "sea"}, "D": {"dee"}, "E": {"ee"}, "G": {"gee", "jee"}}
# she may say "here is" for "here's", that's fine
CONTRACTIONS = {"here's": "here is", "it's": "it is", "that's": "that is", "one's": "one is",
                "there's": "there is", "grownup": "grown up"}


def expand(words):
    out = []
    for w in words:
        out += CONTRACTIONS.get(w.lower().replace("\u2019", "'"), w).split()
    return out


def judge(clip, heard):
    want = expand(tokens(clip["text"]))
    got = expand(tokens(heard))
    spots = letter_spots(clip, want)
    for i in spots:
        if i < len(got) and got[i].lower() in HOMOPHONES.get(want[i], ()):
            got[i] = want[i]
    if [norm(w) for w in want] != [norm(w) for w in got]:
        return "words differ"
    for i in spots:
        if got[i] != want[i]:  # a letter has to come back as the capital letter
            return f"letter heard as {got[i]!r}"
    return None


def check(args):
    clips = load(args.only)
    report_path = os.path.join(args.masters, "check.json")
    report = {}
    if os.path.exists(report_path):
        with open(report_path) as f:
            report = json.load(f)
    bad = []
    for clip in clips:
        path = os.path.join(CLIPS, clip["id"] + ".m4a")
        if not os.path.exists(path):
            print(f"missing {clip['id']}")
            bad.append(clip["id"])
            continue
        if args.cached and clip["id"] in report:
            heard, events = report[clip["id"]]["heard"], report[clip["id"]]["events"]
        else:
            heard, events = stt(path)
        problem = judge(clip, heard)
        secs = duration(path)
        report[clip["id"]] = {"text": clip["text"], "heard": heard, "events": events, "secs": round(secs, 2),
                              "problem": problem}
        flag = problem or ("events " + ", ".join(events) if events else None)
        if flag:
            bad.append(clip["id"])
        print(f"{'FAIL' if problem else ('note' if events else 'ok  ')} {clip['id']:<24} {secs:4.1f}s  "
              f"{heard!r}{'  <- ' + flag if flag else ''}")
        with open(report_path, "w") as f:
            json.dump(report, f, indent=1)
    print(f"\n{len(clips) - len(bad)} of {len(clips)} match. look again: {','.join(bad) or 'none'}")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("command", choices=["make", "check"])
    p.add_argument("--masters", required=True, help="where the raw mp3s and check.json live (outside the repo)")
    p.add_argument("--only", help="comma separated clip ids")
    p.add_argument("--redo", help="comma separated clip ids to delete and make again")
    p.add_argument("--cached", action="store_true", help="check: judge the transcripts in check.json again, no new ones")
    p.add_argument("--max-used", type=int, default=9000, help="stop before the account's character count passes this")
    args = p.parse_args()
    make(args) if args.command == "make" else check(args)


if __name__ == "__main__":
    main()
