# server.py — Flask backend for Kai (chat + TTS + Google CSE + state + auto-search + time/weather intents)
# Run:  PORT=5000 API_KEY_VALUE=... OPENAI_API_KEY=... GOOGLE_API_KEY=... GOOGLE_CSE_ID=...
#       FB_ROOT=... ELEVEN_API_KEY=...  python server.py

import os, json, base64, traceback, re
from datetime import datetime
from functools import wraps
from urllib.parse import urlencode

import requests
from flask import Flask, request, jsonify, send_file, make_response
from flask_cors import CORS
from openai import OpenAI

# ---------- Config ----------
FB_ROOT = os.getenv("FB_ROOT", "https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app")

# Allow both OPENAI_API_KEY and the occasional mis-cased env var
OPENAI_API_KEY      = os.getenv("Openai_API_KEY") or os.getenv("OPENAI_API_KEY")
OPENAI_CHAT_MODEL   = os.getenv("OPENAI_CHAT_MODEL", "gpt-4o")
OPENAI_TAGGER_MODEL = os.getenv("OPENAI_TAGGER_MODEL", "gpt-4o-mini")

GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")
GOOGLE_CSE_ID  = os.getenv("GOOGLE_CSE_ID")

ELEVEN_API_KEY   = os.getenv("Eleven_API_KEY") or os.getenv("ELEVEN_API_KEY")
ELEVEN_VOICE_ID  = os.getenv("ELEVEN_VOICE_ID", "rjyk3ukVFAi8OdkRXxK2")
ELEVEN_MODEL_ID  = os.getenv("ELEVEN_MODEL_ID", "eleven_monolingual_v1")
ELEVEN_VOICE_SETTINGS = {"stability": 0.6, "similarity_boost": 0.75}
CHAT_TTS_DEFAULT = os.getenv("CHAT_TTS", "1") == "1"

openai_client = OpenAI(api_key=OPENAI_API_KEY) if OPENAI_API_KEY else None

# ---------- Traits ----------
PERSONALITY_TRAITS = ["extraversion", "intuition", "feeling", "perceiving"]
MOOD_TRAITS        = ["valence", "energy", "warmth", "confidence", "playfulness", "focus"]

# ---------- Auth ----------
API_KEY_HEADER = "x-api-key"
API_KEY_VALUE  = os.getenv("API_KEY_VALUE", "changeme")
ALLOW_DEV_BYPASS = os.getenv("API_KEY_DEV_BYPASS", "0") == "1"

def _get_client_key():
    v = request.headers.get(API_KEY_HEADER)
    if v: return v.strip()
    auth = request.headers.get("Authorization", "")
    if auth.lower().startswith("bearer "):
        return auth.split(" ", 1)[1].strip()
    qp = request.args.get("api_key")
    if qp: return qp.strip()
    return None

def require_api_key(f):
    @wraps(f)
    def w(*a, **k):
        if request.method == "OPTIONS":
            return make_response("", 200)
        key = _get_client_key()
        if ALLOW_DEV_BYPASS and key is None:
            origin = (request.headers.get("Origin") or "").lower()
            if origin.startswith("http://localhost") or origin.startswith("http://127.0.0.1"):
                print("[auth] DEV_BYPASS for Origin:", origin)
                return f(*a, **k)
        if not API_KEY_VALUE or API_KEY_VALUE == "changeme":
            return jsonify({"status":"error","error":"Server API key not configured (API_KEY_VALUE)."}), 500
        if key != API_KEY_VALUE:
            return jsonify({"status":"error","error":"Invalid or missing API key"}), 403
        return f(*a, **k)
    return w

# ---------- Small helpers ----------
def clamp(v, lo, hi): return max(lo, min(hi, v))

def get_center_values():
    return {
        "personality": {"extraversion": 300, "intuition": 700, "feeling": 800, "perceiving": 600},
        "mood": {"valence": 60, "energy": 65, "warmth": 70, "confidence": 60, "playfulness": 80, "focus": 50},
    }

def ensure_unified_log_exists():
    try:
        url = f"{FB_ROOT}/unified_log.json"
        r = requests.get(url, timeout=6)
        if r.status_code == 200 and r.text == "null":
            requests.put(url, json={}, timeout=6)
    except Exception as e:
        print("ensure_unified_log_exists warn:", e)

ensure_unified_log_exists()

# ---------- Labels / MBTI ----------
PERSONALITY_LABELS = {
    "extraversion": ["withdrawn","introverted","reserved","quiet","neutral","sociable","friendly","talkative","outgoing","vivacious"],
    "intuition":    ["concrete","practical","grounded","realistic","balanced","imaginative","inventive","intuitive","visionary","dreamy"],
    "feeling":      ["detached","objective","logical","analytical","even","gentle","caring","empathetic","warm","compassionate"],
    "perceiving":   ["rigid","structured","methodical","organized","flexible","casual","adaptive","spontaneous","chaotic","free-spirited"],
}
MOOD_LABELS = {
    "valence":     ["depressed","down","flat","neutral","mild","content","pleased","cheerful","happy","euphoric"],
    "energy":      ["exhausted","tired","lethargic","calm","easygoing","rested","lively","active","energized","wired"],
    "warmth":      ["cold","aloof","distant","reserved","neutral","pleasant","friendly","warm","caring","loving"],
    "confidence":  ["insecure","unsure","timid","hesitant","steady","stable","assured","confident","bold","fearless"],
    "playfulness": ["serious","strict","reserved","formal","casual","silly","goofy","cheeky","mischievous","whimsical"],
    "focus":       ["scattered","distracted","unfocused","wandering","neutral","collected","attentive","engaged","laser","locked-in"],
}

def bucket_index(value, max_value): return min(9, int((value / max_value) * 10))
def label_personality(trait, value): return PERSONALITY_LABELS[trait][bucket_index(value, 1000)]
def label_mood(trait, value): return MOOD_LABELS[trait][bucket_index(value, 100)]
def get_all_labels(p, m):
    return {
        "personality_labels": {k: label_personality(k, v) for k, v in p.items()},
        "mood_labels":        {k: label_mood(k, v) for k, v in m.items()},
    }
def calculate_mbti(p):
    return ("E" if p["extraversion"]>=500 else "I") + \
           ("N" if p["intuition"]  >=500 else "S") + \
           ("F" if p["feeling"]    >=500 else "T") + \
           ("P" if p["perceiving"] >=500 else "J")

# ---------- OpenAI ----------
def _openai_chat_with_retry(messages, model, n_tries=3, timeout=30):
    if not openai_client:
        raise RuntimeError("OPENAI_API_KEY missing")
    last_err = None
    for i in range(n_tries):
        try:
            return openai_client.chat.completions.create(
                model=model,
                messages=messages,
                timeout=timeout
            )
        except Exception as e:
            last_err = e
            print(f"[openai] try {i+1}/{n_tries} failed:", e)
    raise last_err

def get_tags_persona(text):
    prompt = f"""
Return ONLY JSON with:
- "tags": string[]
- "persona_delta": {{ extraversion:int(-10..10), intuition:int(-10..10), feeling:int(-10..10), perceiving:int(-10..10) }}
- "mood_delta": {{ valence:int(-5..5), energy:int(-5..5), warmth:int(-5..5), confidence:int(-5..5), playfulness:int(-5..5), focus:int(-5..5) }}
- "context_intensity": "normal"|"high"|"radical"

Text:
\"\"\"{text}\"\"\"""".strip()
    try:
        resp = _openai_chat_with_retry(
            model=OPENAI_TAGGER_MODEL,
            messages=[
                {"role":"system","content":"Respond only with strict JSON."},
                {"role":"user","content":prompt}
            ],
            timeout=20,
        )
        content = (resp.choices[0].message.content or "").strip()
        if content.startswith("```"):
            content = content.strip("`\n ")
            if content.lower().startswith("json"):
                content = content[4:].strip()
        return json.loads(content)
    except Exception as e:
        print("Tagger error:", e)
        return {"tags":[], "persona_delta":{}, "mood_delta":{}, "context_intensity":"normal"}

# ---------- Firebase ----------
def fetch_live_profile(actor_type, actor_id):
    base = f"{FB_ROOT}/{'users' if actor_type=='user' else 'agents'}/{actor_id}"
    centers = get_center_values()
    persona = centers["personality"].copy()
    mood    = centers["mood"].copy()
    try:
        pr = requests.get(f"{base}/personality_current.json", timeout=8)
        if pr.status_code==200 and pr.text and pr.text!="null":
            for k,v in (pr.json() or {}).items():
                if k in persona: persona[k] = int(v)
        mr = requests.get(f"{base}/mood_current.json", timeout=8)
        if mr.status_code==200 and mr.text and mr.text!="null":
            for k,v in (mr.json() or {}).items():
                if k in mood: mood[k] = int(v)
    except Exception as e:
        print("fetch_live_profile error:", e)
    return persona, mood

def write_profile(actor_type, actor_id, persona, mood, summary_payload=None, relationship=None):
    base = f"{FB_ROOT}/{'users' if actor_type=='user' else 'agents'}/{actor_id}"
    try:
        requests.put(f"{base}/personality_current.json", json=persona, timeout=8)
        requests.put(f"{base}/mood_current.json",        json=mood,    timeout=8)
        if summary_payload:
            requests.put(f"{base}/personality_summary.json", json=summary_payload, timeout=8)
        if relationship is not None:
            requests.put(f"{base}/relationship_current.json", json=relationship, timeout=8)
    except Exception as e:
        print("write_profile error:", e)

def log_unified(payload, key=None):
    ts = datetime.now().strftime("%Y%m%dT%H%M%S")
    k  = key or f"{ts}-app-Kai"
    try:
        requests.put(f"{FB_ROOT}/unified_log/{k}.json", json=payload, timeout=8)
    except Exception as e:
        print("unified_log write error:", e)
    return k

# ---------- Flask ----------
app = Flask(__name__)
CORS(app, resources={r"/*": {"origins": os.getenv("ALLOWED_ORIGINS", "*").split(",")}})

@app.route("/", methods=["GET", "HEAD"])
def health(): return "", 200

@app.route("/diag_auth", methods=["GET"])
def diag_auth():
    got = _get_client_key()
    masked = (got[:4]+"…"+got[-4:]) if got and len(got)>8 else (got or "")
    return jsonify({
        "status":"ok",
        "server_key_set": bool(API_KEY_VALUE and API_KEY_VALUE!="changeme"),
        "received_key_masked": masked,
        "has_x_api_key": bool(request.headers.get(API_KEY_HEADER)),
    })

# ---------- State ----------
@app.route("/set_state", methods=["POST","OPTIONS"])
@require_api_key
def set_state():
    try:
        data = request.get_json(force=True) or {}
        actor_type = data.get("actor_type", "agent")
        actor_id   = "Darc" if actor_type=="user" else "Kai"
        personality_current = data.get("personality_current", {})
        mood_current        = data.get("mood_current", {})
        relationship        = data.get("relationship") or data.get("affinity_current")
        write_profile(actor_type, actor_id, personality_current, mood_current, relationship=relationship)
        return jsonify({"status":"ok"})
    except Exception as e:
        traceback.print_exc()
        return jsonify({"status":"error","error":str(e)}), 500

@app.route("/get_state", methods=["GET","OPTIONS"])
@require_api_key
def get_state():
    try:
        actor_type = request.args.get("actor_type", "agent")
        actor_id   = "Darc" if actor_type=="user" else "Kai"
        persona, mood = fetch_live_profile(actor_type, actor_id)
        base = f"{FB_ROOT}/{'users' if actor_type=='user' else 'agents'}/{actor_id}"
        try:
            summary = requests.get(f"{base}/personality_summary.json", timeout=8).json()
        except:
            summary = None
        try:
            relationship = requests.get(f"{base}/relationship_current.json", timeout=8).json()
        except:
            relationship = None
        if not relationship: relationship = {"intimacy":50, "physicality":50}

        recent = []
        try:
            q = f'{FB_ROOT}/unified_log.json?orderBy="$key"&limitToLast=60'
            r = requests.get(q, timeout=8)
            if r.status_code==200 and r.text and r.text!="null":
                all_logs = r.json() or {}
                for k in sorted(all_logs.keys())[-60:]:
                    item = all_logs[k] or {}
                    ad = item.get("actual_deltas") or {}
                    if ad:
                        flat = [{"trait":t,"delta":v,"ts":item.get("timestamp")} for t,v in ad.items() if v]
                        if flat: recent.append({"key":k,"deltas":flat})
        except Exception as e:
            print("recent_deltas error:", e)

        return jsonify({
            "status":"success",
            "personality_current": persona,
            "mood_current": mood,
            "personality_summary": summary,
            "relationship": relationship,
            "affinity_current": relationship,
            "recent_deltas": recent,
        })
    except Exception as e:
        traceback.print_exc()
        return jsonify({"status":"error","error":str(e)}), 500

# ---------- TTS ----------
@app.route("/tts", methods=["POST","OPTIONS"])
@require_api_key
def tts_from_text():
    try:
        data = request.get_json(force=True) or {}
        text = (data.get("text") or "").strip()
        if not text:
            return jsonify({"status":"error","error":"Missing 'text'"}), 400

        if not ELEVEN_API_KEY:
            return jsonify({"status":"success","tts_base64":"","warning":"TTS disabled"}), 200

        resp = requests.post(
            f"https://api.elevenlabs.io/v1/text-to-speech/{ELEVEN_VOICE_ID}",
            headers={"xi-api-key": ELEVEN_API_KEY, "Content-Type":"application/json"},
            json={"text": text, "model_id": ELEVEN_MODEL_ID, "voice_settings": ELEVEN_VOICE_SETTINGS},
            timeout=30,
        )
        if resp.status_code != 200:
            return jsonify({"status":"success","tts_base64":"","warning":"TTS unavailable"}), 200

        with open("/tmp/audio.mp3","wb") as f:
            f.write(resp.content)
        b64 = base64.b64encode(resp.content).decode("utf-8")
        return jsonify({"status":"success","tts_base64": b64})
    except Exception as e:
        traceback.print_exc()
        return jsonify({"status":"error","error":str(e)}), 500

@app.route("/get-audio", methods=["GET"])
def get_audio():
    p = "/tmp/audio.mp3"
    if not os.path.exists(p):
        return jsonify({"status":"error","error":"No audio available"}), 404
    return send_file(p, mimetype="audio/mpeg", as_attachment=True, download_name="kai.mp3")

# ---------- Google Custom Search (with diagnostics) ----------
def google_cse(query: str, num: int = 5, *, date_restrict: str = "d1",
               lang: str = "en", gl: str = "us", news_bias: bool = True):
    """
    Returns (results, diag) where:
      results: list[{title, link, displayLink, snippet, publishedAt}]
      diag:    dict with raw status/error info
    date_restrict: dN / wN / mN / yN  (JSON CSE doesn't support hours)
    """
    def _normalize_date_restrict(v: str):
        """Ensure value is one of dN/wN/mN/yN. Convert hN → d1; invalid → None (omit)."""
        if not v:
            return None
        v = v.strip().lower()
        if v.startswith("h"):
            return "d1"
        if (len(v) >= 2 and v[0] in ("d", "w", "m", "y") and v[1:].isdigit()):
            return f"{v[0]}{max(1, int(v[1:]))}"
        return None

    diag = {"ok": False, "status": None, "error": None, "url": None}

    if not GOOGLE_API_KEY or not GOOGLE_CSE_ID:
        diag["error"] = "GOOGLE_API_KEY or GOOGLE_CSE_ID missing"
        return [], diag

    q = query
    if news_bias:
        q = (f'{query} (site:news.google.com OR site:reuters.com OR site:apnews.com '
             f'OR site:bbc.com OR site:cnn.com OR site:aljazeera.com OR site:theguardian.com)')

    params = {
        "key": GOOGLE_API_KEY,
        "cx": GOOGLE_CSE_ID,
        "q": q,
        "num": max(1, min(10, num)),
        "hl": lang,
        "gl": gl,
        "safe": "off",
        # "sort": "date",  # enable only if your CSE has a sort option configured
    }
    dr = _normalize_date_restrict(date_restrict)
    if dr:
        params["dateRestrict"] = dr

    try:
        url = "https://www.googleapis.com/customsearch/v1?" + urlencode(params)
        diag["url"] = url
        r = requests.get(url, timeout=12)
        diag["status"] = r.status_code

        if r.status_code != 200:
            try:
                j = r.json()
                diag["error"] = (j.get("error") or {}).get("message") or r.text[:200]
            except Exception:
                diag["error"] = r.text[:200]
            return [], diag

        j = r.json() or {}
        if "error" in j:
            diag["error"] = (j.get("error") or {}).get("message")
            return [], diag

        items = j.get("items", []) or []

        def extract_time(meta):
            if not meta:
                return ""
            m = meta[0] if isinstance(meta, list) else meta
            for k in ("og:updated_time","article:modified_time","article:published_time","pubdate","date","og:pubdate"):
                v = m.get(k)
                if v:
                    return v
            return ""

        out = []
        for it in items[:num]:
            pagemap = (it.get("pagemap") or {}).get("metatags") or []
            out.append({
                "title": it.get("title",""),
                "link": it.get("link",""),
                "displayLink": it.get("displayLink",""),
                "snippet": it.get("snippet",""),
                "publishedAt": extract_time(pagemap),
            })
        diag["ok"] = True
        if not out:
            diag["error"] = "No items returned (engine restrictions or empty results)."
        return out, diag
    except Exception as e:
        diag["error"] = f"Exception: {e}"
        return [], diag

@app.route("/search", methods=["POST","OPTIONS"])
@require_api_key
def search():
    try:
        data = request.get_json(force=True) or {}
        q = (data.get("q") or "").strip()
        if not q:
            return jsonify({"status":"error","error":"Missing 'q'"}), 400
        results, diag = google_cse(q, num=int(data.get("num", 5)), date_restrict=data.get("date","d1"))
        return jsonify({"status":"success","results": results, "diag": diag})
    except Exception as e:
        traceback.print_exc()
        return jsonify({"status":"error","error":str(e)}), 500

@app.get("/news")
@require_api_key
def news():
    q = (request.args.get("q") or "").strip()
    date_restrict = request.args.get("date", "d1")  # valid default
    num = int(request.args.get("n", 5))
    if not q:
        return jsonify({"status":"error","error":"missing q"}), 400
    results, diag = google_cse(q, num=num, date_restrict=date_restrict, news_bias=True)
    return jsonify({"status":"success","articles": results, "diag": diag})

@app.get("/diag_cse")
@require_api_key
def diag_cse():
    q = request.args.get("q", "breaking news")
    results, diag = google_cse(q, num=3, date_restrict="d1")
    return jsonify({"status":"ok", "query": q, "count": len(results), "diag": diag, "sample": results})

# ---------- Internal web / intent helpers ----------
_NEWSY = re.compile(
    r"(?i)\b("
    r"latest|today|tonight|now|right\s*now|breaking|this week|this month|recent|update|"
    r"news|headlines|top stories|trending|"
    r"who won|final score|live score|score|results|fixture|match|game|kickoff|tipoff|"
    r"release date|when is|schedule|"
    r"earnings|stock|share price|ipo|crypto|bitcoin|ethereum|exchange rate|"
    r"traffic|queue times|flight status|"
    r"covid|inflation|rate|mortgage|fed|election|poll|"
    r"nba|nfl|mlb|nhl|epl|uefa|f1|formula 1|tennis|golf"
    r")\b"
)
_TIMEY    = re.compile(r"(?i)\b(time|current time|what time is it|time in)\b")
_WEATHERY = re.compile(r"(?i)\b(weather|forecast|temperature|rain|wind|humidity|uv index)\b")

_YEAR   = re.compile(r"\b(19\d{2}|20[0-5]\d)\b")
_URLISH = re.compile(r"https?://|www\.", re.IGNORECASE)

# --- Native Time intent ---
_CITY_TO_TZ = {
    "manama":"Asia/Bahrain", "bahrain":"Asia/Bahrain",
    "dubai":"Asia/Dubai", "abu dhabi":"Asia/Dubai",
    "riyadh":"Asia/Riyadh", "doha":"Asia/Qatar", "kuwait":"Asia/Kuwait",
    "london":"Europe/London", "paris":"Europe/Paris", "berlin":"Europe/Berlin",
    "madrid":"Europe/Madrid", "rome":"Europe/Rome",
    "new york":"America/New_York", "nyc":"America/New_York", "los angeles":"America/Los_Angeles",
    "san francisco":"America/Los_Angeles", "chicago":"America/Chicago", "austin":"America/Chicago",
    "tokyo":"Asia/Tokyo", "singapore":"Asia/Singapore", "hong kong":"Asia/Hong_Kong",
    "mumbai":"Asia/Kolkata", "delhi":"Asia/Kolkata", "sydney":"Australia/Sydney",
    "cairo":"Africa/Cairo", "istanbul":"Europe/Istanbul",
}

def _extract_place(q, keywords=("time in", "weather in", "forecast in")):
    low = q.lower()
    for kw in keywords:
        if kw in low:
            return low.split(kw,1)[1].strip(" ?.,")
    m = re.search(r"(?i)\bin\s+([a-zA-Z\s,]+)$", q.strip())
    return (m.group(1).strip(" ?.,") if m else "").lower()

def _current_time_payload(q):
    place = _extract_place(q, ("time in",))
    tz = None
    if place in _CITY_TO_TZ:
        tz = _CITY_TO_TZ[place]
    elif place:
        try:
            all_tz = requests.get("http://worldtimeapi.org/api/timezone", timeout=8).json()
            cand = [z for z in all_tz if place.replace(" ", "_") in z.lower()]
            tz = cand[0] if cand else None
        except Exception as e:
            print("time zone list warn:", e)
    if not tz:
        tz = "Asia/Bahrain"  # default
    try:
        r = requests.get(f"http://worldtimeapi.org/api/timezone/{tz}", timeout=8)
        j = r.json()
        iso = j.get("datetime")
        offset = j.get("utc_offset")
        if iso:
            dt = iso.replace("T", " ").split(".")[0]
            return f"Current time in {tz} is **{dt}** (UTC{offset})."
    except Exception as e:
        print("time fetch warn:", e)
    try:
        local_now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        return f"Current server time is **{local_now}** (local timezone)."
    except Exception:
        return "Sorry—I couldn’t get the time right now, even locally."

# --- Native Weather intent (Open-Meteo) ---
def _geocode_city(city_name):
    try:
        r = requests.get(
            "https://geocoding-api.open-meteo.com/v1/search",
            params={"name": city_name, "count": 1, "language": "en", "format": "json"},
            timeout=8,
        )
        j = r.json() or {}
        if (j.get("results") or []):
            it = j["results"][0]
            return it["latitude"], it["longitude"], it.get("name"), it.get("country")
    except Exception as e:
        print("geocode warn:", e)
    return None, None, None, None

def _current_weather_payload(q):
    city = _extract_place(q, ("weather in", "forecast in"))
    if not city:
        city = "Manama"
    lat, lon, name, country = _geocode_city(city)
    if lat is None or lon is None:
        return "Sorry—I couldn’t resolve that location."
    try:
        r = requests.get(
            "https://api.open-meteo.com/v1/forecast",
            params={"latitude": lat, "longitude": lon, "current": "temperature_2m,wind_speed_10m,relative_humidity_2m"},
            timeout=8,
        )
        j = r.json() or {}
        cur = j.get("current") or {}
        t = cur.get("temperature_2m")
        w = cur.get("wind_speed_10m")
        h = cur.get("relative_humidity_2m")
        loc = f"{name}, {country}" if country else (name or city.title())
        parts = []
        if t is not None: parts.append(f"**{t}°C**")
        if h is not None: parts.append(f"{h}% RH")
        if w is not None: parts.append(f"{w} m/s wind")
        if not parts:
            return f"Weather for {loc}: data unavailable."
        return f"Weather now in {loc}: " + ", ".join(parts) + "."
    except Exception as e:
        print("weather warn:", e)
        return "Sorry—I couldn’t fetch the weather right now."

def should_search(user_text: str) -> bool:
    """
    Decide if we should hit Google CSE for fresh/contextual info.
    We handle time/weather natively; search is for news/results/prices/etc.
    """
    t = (user_text or "").strip()
    if not t:
        return False
    if _TIMEY.search(t) or _WEATHERY.search(t):
        return False
    if "search" in t.lower() or _URLISH.search(t):
        return True
    if _NEWSY.search(t):
        return True
    if _YEAR.search(t):
        return True
    if "?" in t and len(t.split()) > 10:
        return True
    short = t.lower()
    if short in {"news", "headlines", "top news"}:
        return True
    return False

def build_web_context(snippets):
    lines = []
    for i, r in enumerate(snippets[:5], 1):
        title   = (r.get("title") or "")[:160]
        url     = r.get("link") or ""
        snippet = (r.get("snippet") or "")[:300]
        lines.append(f"[{i}] {title}\n{url}\n— {snippet}")
    if not lines:
        return ""
    return (
        "Use the following web findings **only if helpful**. "
        "Cite sources inline as [#] when stating specific facts.\n\n" +
        "\n\n".join(lines)
    )

# ---------- Chat ----------
@app.route("/chat", methods=["POST","OPTIONS"])
@require_api_key
def chat_text():
    try:
        data = request.get_json(force=True) or {}
        user_text = (data.get("text") or "").strip()
        if not user_text:
            return jsonify({"status":"error","error":"Missing 'text'"}), 400

        source     = data.get("source","app")
        actor_type = data.get("actor_type","agent")
        actor_id   = "Kai" if actor_type=="agent" else "Darc"
        model      = data.get("model", OPENAI_CHAT_MODEL)
        adapt_user = bool(data.get("adapt_user", False))
        ctx_turns  = int(data.get("ctx_turns", 20))

        ts_user = datetime.now().strftime("%Y%m%dT%H%M%S")
        log_unified({"user_input": user_text, "source": source, "timestamp": ts_user},
                    key=f"{ts_user}-{source}-USER")

        kai_persona, kai_mood   = fetch_live_profile("agent","Kai")
        user_persona, user_mood = fetch_live_profile("user","Darc")

        # Build short text history
        history = []
        try:
            q = f'{FB_ROOT}/unified_log.json?orderBy="$key"&limitToLast={max(10, ctx_turns)}'
            r = requests.get(q, timeout=6)
            if r.status_code==200 and r.text and r.text!="null":
                logs = r.json() or {}
                for k in sorted(logs.keys())[-ctx_turns:]:
                    item = logs[k] or {}
                    if item.get("user_input"): history.append(f"User: {item.get('user_input')}")
                    if item.get("content"):    history.append(f"Kai: {item.get('content')}")
        except Exception as e:
            print("history warn:", e)

        persona_summary = f"Kai MBTI guess: {calculate_mbti(kai_persona)}. Personality={kai_persona}. Mood={kai_mood}."
        user_summary    = f"User personality={user_persona}. User mood={user_mood}." if adapt_user else ""

        # ---- Decision debug (to see what fired) ----
        decision_debug = {"matched_time": False, "matched_weather": False, "web_triggered": False}

        # ---- Native live intents (time/weather) ----
        live_used = None
        live_text = ""
        if _TIMEY.search(user_text):
            decision_debug["matched_time"] = True
            live_used = "time"
            live_text = _current_time_payload(user_text)
        elif _WEATHERY.search(user_text):
            decision_debug["matched_weather"] = True
            live_used = "weather"
            live_text = _current_weather_payload(user_text)

        # --- Short-circuit TIME replies so the model can't override ---
        if live_used == "time" and live_text:
            ts = datetime.now().strftime("%Y%m%dT%H%M%S")
            log_unified({
                "user_input": user_text, "content": live_text,
                "timestamp": ts, "web_used": False, "live_used": live_used,
                "decision_debug": decision_debug,
            }, key=f"{ts}-{source}-Kai")
            return jsonify({
                "status":"success",
                "kai_response": live_text,
                "kai_mbti": calculate_mbti(kai_persona),
                "kai_profile": kai_persona,
                "kai_mood": kai_mood,
                "kai_summary": "",
                "tags": [],
                "tts_base64": "",
                "persona_delta": {},
                "mood_delta": {},
                "actual_deltas": {},
                "web_used": False,
                "live_used": live_used,
                "decision_debug": decision_debug,
            })

        # ---- Web search for news/other live topics ----
        web_used = False
        web_context = ""
        if not live_used and should_search(user_text):
            headlineish = re.search(r"(?i)\b(news|headlines|breaking|top stories|latest)\b", user_text) is not None
            if headlineish:
                snippets, cse_diag = google_cse(user_text, num=5, date_restrict="d1")
                decision_debug["web_triggered"] = True
                web_used = True
                if snippets:
                    lines = []
                    for i, it in enumerate(snippets[:5], 1):
                        title = (it.get("title") or "").strip()
                        domain = (it.get("displayLink") or "").strip()
                        if title:
                            lines.append(f"{i}. {title}" + (f" — {domain}" if domain else ""))
                    reply = "Here are some current headlines:\n" + ("\n".join(lines) if lines else "No headlines found.")
                else:
                    hint = cse_diag.get("error") or "unknown error"
                    reply = ("I couldn’t fetch fresh headlines right now.\n\n"
                             f"• Google CSE said: {hint}\n"
                             "• Check the JSON API is enabled & billing active; use a server key "
                             "without HTTP referrer restrictions; and make sure the engine searches the web.")
                ts = datetime.now().strftime("%Y%m%dT%H%M%S")
                log_unified({
                    "user_input": user_text, "content": reply,
                    "timestamp": ts, "web_used": web_used, "live_used": None,
                    "decision_debug": decision_debug,
                }, key=f"{ts}-{source}-Kai")
                return jsonify({
                    "status": "success",
                    "kai_response": reply,
                    "kai_mbti": calculate_mbti(kai_persona),
                    "kai_profile": kai_persona,
                    "kai_mood": kai_mood,
                    "kai_summary": "",
                    "tags": [],
                    "tts_base64": "",
                    "persona_delta": {},
                    "mood_delta": {},
                    "actual_deltas": {},
                    "web_used": web_used,
                    "live_used": None,
                    "decision_debug": decision_debug,
                })

            # Otherwise pass snippets as WEB CONTEXT for grounded Q&A
            snippets, _diag = google_cse(user_text, num=5, date_restrict="d1")
            decision_debug["web_triggered"] = bool(snippets)
            web_context = build_web_context(snippets)
            web_used = bool(web_context)

        # System prompt (prefer web context for time-sensitive facts; include live chunk for weather)
        system_prompt = (
            "You are Kai: warm, witty, emotionally attuned.\n"
            "Answer concisely and helpfully. If WEB CONTEXT is provided, **treat it as the source of truth** "
            "for time-sensitive or factual claims and cite as [1], [2], etc. If not relevant, ignore it.\n\n"
            f"{persona_summary}\n{user_summary}\n"
            "Conversation so far:\n" + "\n".join(history[-20:])
        )
        if web_context:
            system_prompt += "\n\n--- WEB CONTEXT START ---\n" + web_context + "\n--- WEB CONTEXT END ---\n"
        if live_used and live_text:  # weather path (time already short-circuited)
            system_prompt += f"\n\n--- LIVE DATA ({live_used.upper()}) ---\n{live_text}\n--- END LIVE DATA ---\n"

        # Call OpenAI
        try:
            resp = _openai_chat_with_retry(
                model=model,
                messages=[{"role":"system","content":system_prompt},
                          {"role":"user","content":user_text}],
                timeout=40,
            )
            reply = (resp.choices[0].message.content or "").strip()
        except Exception as e:
            print("openai fatal:", e)
            reply = live_text or "Temporary hiccup on my side. Try again?"

        if not reply:
            reply = live_text or "I’m here—network was flaky for a moment. Try again?"

        # Tag & update persona/mood
        tags_result   = get_tags_persona(reply) or {}
        persona_delta = tags_result.get("persona_delta",{}) or {}
        mood_delta    = tags_result.get("mood_delta",{}) or {}
        tags          = tags_result.get("tags",[]) or []
        context       = tags_result.get("context_intensity","normal")

        actual_deltas = {}
        for t in PERSONALITY_TRAITS:
            d = clamp(int(persona_delta.get(t,0)),-10,10)
            kai_persona[t] = clamp(kai_persona[t]+d, 0, 1000); actual_deltas[t]=d
        for t in MOOD_TRAITS:
            d = clamp(int(mood_delta.get(t,0)),-5,5)
            kai_mood[t] = clamp(kai_mood[t]+d, 0, 100); actual_deltas[t]=d

        labels = get_all_labels(kai_persona, kai_mood)
        mbti   = calculate_mbti(kai_persona)
        summary = f"MBTI: {mbti}. Personality: " + \
                  ", ".join([f"{k}: {labels['personality_labels'][k]}" for k in PERSONALITY_TRAITS]) + \
                  ". Mood: " + ", ".join([f"{k}: {labels['mood_labels'][k]}" for k in MOOD_TRAITS]) + "."

        ts = datetime.now().strftime("%Y%m%dT%H%M%S")
        log_unified({
            "user_input": user_text, "content": reply, "tags": tags,
            "persona_delta": persona_delta, "mood_delta": mood_delta,
            "actual_deltas": actual_deltas, "context": context, "timestamp": ts,
            "mbti": mbti, "profile": kai_persona, "mood": kai_mood,
            "labels": labels, "profile_summary": summary,
            "web_used": web_used, "live_used": live_used,
            "decision_debug": decision_debug,
        }, key=f"{ts}-{source}-Kai")

        write_profile("agent","Kai", kai_persona, kai_mood,
                      summary_payload={"summary":summary,"mbti":mbti,"labels":labels})

        # TTS (optional)
        tts_b64 = ""
        if CHAT_TTS_DEFAULT and ELEVEN_API_KEY:
            try:
                tts_resp = requests.post(
                    f"https://api.elevenlabs.io/v1/text-to-speech/{ELEVEN_VOICE_ID}",
                    headers={"xi-api-key": ELEVEN_API_KEY, "Content-Type":"application/json"},
                    json={"text": reply, "model_id": ELEVEN_MODEL_ID, "voice_settings": ELEVEN_VOICE_SETTINGS},
                    timeout=25,
                )
                if tts_resp.status_code == 200:
                    with open("/tmp/audio.mp3","wb") as f:
                        f.write(tts_resp.content)
                    tts_b64 = base64.b64encode(tts_resp.content).decode("utf-8")
            except Exception as e:
                print("TTS warn:", e)

        return jsonify({
            "status":"success",
            "kai_response": reply,
            "kai_mbti": mbti,
            "kai_profile": kai_persona,
            "kai_mood": kai_mood,
            "kai_summary": summary,
            "tags": tags,
            "tts_base64": tts_b64,
            "persona_delta": persona_delta,
            "mood_delta": mood_delta,
            "actual_deltas": actual_deltas,
            "web_used": web_used,
            "live_used": live_used,      # 'time' or 'weather' when native live data was used
            "decision_debug": decision_debug,
        })
    except Exception as e:
        traceback.print_exc()
        return jsonify({"status":"error","error":str(e)}), 500

# ---------- diag ----------
@app.route("/diag", methods=["GET"])
def diag():
    return jsonify({
        "status":"ok",
        "env":{
            "OPENAI_API_KEY_set": bool(OPENAI_API_KEY),
            "API_KEY_VALUE_set": bool(API_KEY_VALUE and API_KEY_VALUE!="changeme"),
            "FB_ROOT_ok": bool(FB_ROOT.startswith("http")),
            "GOOGLE_API_KEY_set": bool(GOOGLE_API_KEY),
            "GOOGLE_CSE_ID_set": bool(GOOGLE_CSE_ID),
            "ELEVEN_API_KEY_set": bool(ELEVEN_API_KEY),
        }
    })

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    print(f"Starting Flask on 0.0.0.0:{port}")
    app.run(host="0.0.0.0", port=port)