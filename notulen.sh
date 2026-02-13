#!/usr/bin/env bash
set -euo pipefail

# =========================
# Config default
# =========================
LANGUAGE="Indonesian"
MODEL="medium"
FP16="False"
DEVICE="auto"
BASE_OUTDIR="./notulen"
KEEP_TEMP="no"
TRANSCRIBE_ONLY="no"

usage() {
  cat <<'EOF'
Usage:
  ./notulen.sh [options] "<nama_rapat>" <audio_file>
  ./notulen.sh "<nama_rapat>" MakeNotulen
  ./notulen.sh "<nama_rapat_final>" MakeNotulenFromParts <run_date> <part_prefix>

Options:
  -m, --model        Whisper model (default: medium)
  -l, --language     Language (default: Indonesian)
  -d, --device       Device (auto, cpu, cuda) (default: auto)
  -f, --fp16         Use fp16 (True/False) (default: False)
  -b, --base-outdir  Base output dir (default: ./notulen)
  -k, --keep-temp    Keep preprocessed wav (default: no)
  -t, --transcribe-only  Stop after transcribe (skip NOTULENSI + RTL)
  -h, --help         Help

Env:
  OPENAI_API_KEY     If set, will generate NOTULENSI.md + RTL.csv via OpenAI API.
  OPENAI_MODEL       Optional (default: gpt-5-mini)

Examples:
  ./notulen.sh "Rapat Koordinasi Carik" rapat.wav
  ./notulen.sh -m small -d cpu "Rapat Koordinasi Carik" rapat.wav
  ./notulen.sh -m medium -d cuda -f True "Rapat Koordinasi Carik" rapat.wav
  ./notulen.sh -m medium -d auto -f True "Rapat Koordinasi Carik" rapat.wav
  ./notulen.sh -m small -d cpu -t "Rapat Koordinasi Carik" rapat.wav
  ./notulen.sh "Rapat Koordinasi Carik" MakeNotulen
  ./notulen.sh "Rapat Koordinasi DTSEN" MakeNotulenFromParts 2026-02-13 2026-02-10
  OPENAI_API_KEY=xxx ./notulen.sh "FGD DTSEN" rekaman.mp3
EOF
}

slugify() {
  # lower, replace spaces with _, remove weird chars
  echo "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[[:space:]]+/_/g; s/[^a-z0-9_()-]+//g; s/_+/_/g; s/^_+|_+$//g'
}

# =========================
# Parse args
# =========================
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--model) MODEL="$2"; shift 2;;
    -l|--language) LANGUAGE="$2"; shift 2;;
    -d|--device) DEVICE="$2"; shift 2;;
    -f|--fp16) FP16="$2"; shift 2;;
    -b|--base-outdir) BASE_OUTDIR="$2"; shift 2;;
    -k|--keep-temp) KEEP_TEMP="yes"; shift 1;;
    -t|--transcribe-only) TRANSCRIBE_ONLY="yes"; shift 1;;
    -h|--help) usage; exit 0;;
    -*) echo "Unknown option: $1"; usage; exit 1;;
    *) ARGS+=("$1"); shift;;
  esac
done

if [[ ${#ARGS[@]} -lt 2 ]]; then
  echo "Error: butuh <nama_rapat> dan <audio_file> atau MakeNotulen."
  usage
  exit 1
fi

MEETING_NAME="${ARGS[0]}"
INPUT_ARG="${ARGS[1]}"
MAKE_NOTULEN_ONLY="no"
MAKE_NOTULEN_FROM_PARTS="no"
PARTS_DATE=""
PARTS_PREFIX=""

if [[ "$INPUT_ARG" == "MakeNotulen" ]]; then
  MAKE_NOTULEN_ONLY="yes"
elif [[ "$INPUT_ARG" == "MakeNotulenFromParts" ]]; then
  MAKE_NOTULEN_FROM_PARTS="yes"
  if [[ ${#ARGS[@]} -lt 4 ]]; then
    echo "Error: mode MakeNotulenFromParts butuh <run_date> dan <part_prefix>."
    usage
    exit 1
  fi
  PARTS_DATE="${ARGS[2]}"
  PARTS_PREFIX="${ARGS[3]}"
else
  AUDIO_FILE="$INPUT_ARG"
fi

if [[ "$MAKE_NOTULEN_ONLY" != "yes" && "$MAKE_NOTULEN_FROM_PARTS" != "yes" ]]; then
  if [[ ! -f "$AUDIO_FILE" ]]; then
    echo "Error: file audio tidak ditemukan: $AUDIO_FILE"
    exit 1
  fi
fi

WHISPER_CMD="whisper"
if [[ "$MAKE_NOTULEN_ONLY" != "yes" && "$MAKE_NOTULEN_FROM_PARTS" != "yes" ]]; then
  command -v ffmpeg >/dev/null 2>&1 || { echo "Error: ffmpeg belum terpasang."; exit 1; }
  # Whisper command: prefer whisper; fallback to pipx run
  if ! command -v whisper >/dev/null 2>&1; then
    if command -v pipx >/dev/null 2>&1; then
      WHISPER_CMD="pipx run openai-whisper"
    else
      echo "Error: 'whisper' tidak ditemukan dan pipx tidak ada."
      exit 1
    fi
  fi
fi

# =========================
# Folder by date + meeting
# =========================
TODAY="$(date +%F)"                # YYYY-MM-DD
MEETING_SLUG="$(slugify "$MEETING_NAME")"

if [[ "$MAKE_NOTULEN_ONLY" == "yes" ]]; then
  # Pick latest existing folder for this meeting
  OUTDIR="$(ls -td "${BASE_OUTDIR}"/*/"${MEETING_SLUG}" 2>/dev/null | head -n 1 || true)"
  if [[ -z "${OUTDIR:-}" || ! -d "$OUTDIR" ]]; then
    echo "Error: folder notulen untuk rapat ini tidak ditemukan."
    exit 1
  fi
elif [[ "$MAKE_NOTULEN_FROM_PARTS" == "yes" ]]; then
  TODAY="$PARTS_DATE"
  OUTDIR="${BASE_OUTDIR}/${PARTS_DATE}/${MEETING_SLUG}"
  mkdir -p "$OUTDIR"
else
  OUTDIR="${BASE_OUTDIR}/${TODAY}/${MEETING_SLUG}"
  mkdir -p "$OUTDIR"
fi

if [[ "$MAKE_NOTULEN_ONLY" != "yes" && "$MAKE_NOTULEN_FROM_PARTS" != "yes" ]]; then
  # Copy original audio for traceability
  cp -f "$AUDIO_FILE" "$OUTDIR/"
fi

if [[ "$MAKE_NOTULEN_ONLY" != "yes" && "$MAKE_NOTULEN_FROM_PARTS" != "yes" ]]; then
  BASENAME="$(basename "$AUDIO_FILE")"
  STEM="${BASENAME%.*}"
  PRE_WAV="${OUTDIR}/${STEM}__preproc.wav"
elif [[ "$MAKE_NOTULEN_FROM_PARTS" == "yes" ]]; then
  STEM="combined"
else
  # best effort: infer STEM from existing progress files
  STEM="$(ls -1 "${OUTDIR}"/*__whisper.progress.txt 2>/dev/null | head -n 1 | xargs -r basename | sed -E 's/__whisper\.progress\.txt$//' )"
fi

echo "========================================"
echo "Tanggal     : $TODAY"
echo "Rapat       : $MEETING_NAME"
echo "Output dir  : $OUTDIR"
if [[ "$MAKE_NOTULEN_ONLY" != "yes" && "$MAKE_NOTULEN_FROM_PARTS" != "yes" ]]; then
  echo "Audio       : $AUDIO_FILE"
elif [[ "$MAKE_NOTULEN_FROM_PARTS" == "yes" ]]; then
  echo "Audio       : (skip, merge parts ${PARTS_PREFIX}_part_*.flac dari ${PARTS_DATE})"
else
  echo "Audio       : (skip, MakeNotulen)"
fi
if [[ "$MAKE_NOTULEN_ONLY" == "yes" || "$MAKE_NOTULEN_FROM_PARTS" == "yes" ]]; then
  echo "Model       : (skip transcribe)"
elif [[ "$DEVICE" == "auto" ]]; then
  echo "Model       : $MODEL | Lang: $LANGUAGE | device: auto (try cuda->cpu) | fp16: $FP16"
else
  echo "Model       : $MODEL | Lang: $LANGUAGE | device: $DEVICE | fp16: $FP16"
fi
echo "========================================"

# =========================
# 1) Preprocess audio
# =========================
if [[ "$MAKE_NOTULEN_ONLY" != "yes" && "$MAKE_NOTULEN_FROM_PARTS" != "yes" ]]; then
  echo "[1/3] Preprocess audio (mono 16kHz + dynaudnorm)..."
  ffmpeg -y -hide_banner -loglevel error \
    -i "$AUDIO_FILE" \
    -ac 1 -ar 16000 \
    -af "dynaudnorm=f=150:g=15" \
    "$PRE_WAV"
fi

# =========================
# 2) Whisper transcribe
# =========================
if [[ "$MAKE_NOTULEN_ONLY" != "yes" && "$MAKE_NOTULEN_FROM_PARTS" != "yes" ]]; then
  echo "[2/3] Transcribe with Whisper..."
fi

WHISPER_LOG="${OUTDIR}/whisper.log"
WHISPER_PROGRESS="${OUTDIR}/${STEM}__whisper.progress.txt"
CUDA_ERROR_RE="torch.cuda.is_available\\(\\) is False|Attempting to deserialize object on a CUDA device|CUDA device"

normalize_ts() {
  local ts="$1"
  local parts
  parts="$(echo "$ts" | awk -F: '{print NF}')"
  if [[ "$parts" -eq 2 ]]; then
    echo "00:$ts"
  else
    echo "$ts"
  fi
}

get_resume_ts() {
  if [[ ! -f "$WHISPER_PROGRESS" ]]; then
    return 1
  fi
  local last
  last="$(grep -oE '\\[[0-9:.]+ --> [0-9:.]+\\]' "$WHISPER_PROGRESS" | tail -n 1 | sed -E 's/.*--> ([0-9:.]+)\\].*/\\1/' || true)"
  if [[ -z "$last" ]]; then
    return 1
  fi
  normalize_ts "$last"
}

run_whisper() {
  local device="$1"
  local fp16="$2"
  local append="$3"
  local cmd=("$WHISPER_CMD" "$PRE_WAV" \
    --language "$LANGUAGE" \
    --model "$MODEL" \
    --device "$device" \
    --fp16 "$fp16" \
    --output_dir "$OUTDIR" \
    --output_format "all" \
    --verbose True)

  # Stream progress to file so partial output is visible if process fails.
  if [[ "$append" != "yes" ]]; then
    : > "$WHISPER_PROGRESS"
  fi
  if command -v stdbuf >/dev/null 2>&1; then
    stdbuf -oL -eL "${cmd[@]}" 2> "$WHISPER_LOG" | tee -a "$WHISPER_PROGRESS"
  else
    "${cmd[@]}" 2> "$WHISPER_LOG" | tee -a "$WHISPER_PROGRESS"
  fi
}

if [[ "$MAKE_NOTULEN_ONLY" != "yes" && "$MAKE_NOTULEN_FROM_PARTS" != "yes" ]]; then
  RESUME_TS="$(get_resume_ts || true)"
  RESUME_MODE="no"
  PREV_TXT=""
  if [[ -n "${RESUME_TS:-}" ]]; then
    RESUME_MODE="yes"
    echo "Resume dari timestamp terakhir: $RESUME_TS"
    ORIGINAL_AUDIO="${OUTDIR}/${BASENAME}"
    PRE_WAV="${OUTDIR}/${STEM}__preproc_resume.wav"
    # Recreate preproc from resume timestamp
    ffmpeg -y -hide_banner -loglevel error \
      -ss "$RESUME_TS" \
      -i "$ORIGINAL_AUDIO" \
      -ac 1 -ar 16000 \
      -af "dynaudnorm=f=150:g=15" \
      "$PRE_WAV"
    PREV_TXT="$(ls -t "$OUTDIR"/*.txt 2>/dev/null | head -n 1 || true)"
  fi

  if [[ "$DEVICE" == "auto" ]]; then
    if run_whisper "cuda" "$FP16" "$RESUME_MODE"; then
      DEVICE="cuda"
    else
      if grep -Eiq "$CUDA_ERROR_RE" "$WHISPER_LOG"; then
        echo "CUDA tidak tersedia, fallback ke CPU."
        run_whisper "cpu" "False" "$RESUME_MODE"
        DEVICE="cpu"
      else
        cat "$WHISPER_LOG" >&2
        exit 1
      fi
    fi
  elif [[ "$DEVICE" == "cuda" ]]; then
    if ! run_whisper "cuda" "$FP16" "$RESUME_MODE"; then
      cat "$WHISPER_LOG" >&2
      exit 1
    fi
  else
    # CPU mode: ensure fp16 False
    if [[ "$FP16" == "True" || "$FP16" == "true" ]]; then
      echo "FP16 diabaikan pada CPU. Memakai fp16=False."
    fi
    if ! run_whisper "cpu" "False" "$RESUME_MODE"; then
      cat "$WHISPER_LOG" >&2
      exit 1
    fi
  fi
fi

if [[ "$MAKE_NOTULEN_FROM_PARTS" == "yes" ]]; then
  echo "[1/1] Merge transkrip part sebelum MakeNotulen..."
  WHISPER_PROGRESS="${OUTDIR}/combined__whisper.progress.txt"
  : > "$WHISPER_PROGRESS"
  shopt -s nullglob
  part_dirs=("${BASE_OUTDIR}/${PARTS_DATE}/transkrip_${PARTS_PREFIX}_part_"*)
  shopt -u nullglob
  merged_count=0
  for part_dir in "${part_dirs[@]}"; do
    [[ -d "$part_dir" ]] || continue
    part_name="$(basename "$part_dir")"
    part_stem="${part_name#transkrip_}"
    preferred_txt="${part_dir}/${part_stem}__preproc.txt"
    if [[ -f "$preferred_txt" ]]; then
      src_txt="$preferred_txt"
    else
      src_txt="$(find "$part_dir" -maxdepth 1 -type f -name "*.txt" ! -name "*__whisper.progress.txt" | sort | head -n 1 || true)"
    fi
    if [[ -z "${src_txt:-}" || ! -f "$src_txt" ]]; then
      echo "Skip: txt part belum ada -> $part_dir"
      continue
    fi
    {
      echo "===== ${part_stem} ====="
      cat "$src_txt"
      echo
    } >> "$WHISPER_PROGRESS"
    merged_count=$((merged_count + 1))
  done
  if [[ "$merged_count" -eq 0 ]]; then
    echo "Error: tidak ada transkrip part yang bisa digabung."
    exit 1
  fi
  TXT_OUT="$WHISPER_PROGRESS"
else
  TXT_OUT="${OUTDIR}/${STEM}__preproc.txt"
  if [[ ! -f "$TXT_OUT" ]]; then
    # beberapa build whisper menamai output sama dengan input tanpa suffix; cari txt terbaru
    TXT_OUT="$(ls -t "$OUTDIR"/*.txt 2>/dev/null | head -n 1 || true)"
  fi
fi

# If resume created a new txt, merge with previous txt for continuity
MERGED_TXT=""
if [[ "$MAKE_NOTULEN_ONLY" != "yes" && "$MAKE_NOTULEN_FROM_PARTS" != "yes" ]]; then
  if [[ -n "${PREV_TXT:-}" && -f "$PREV_TXT" && -n "${TXT_OUT:-}" && -f "$TXT_OUT" && "$PREV_TXT" != "$TXT_OUT" ]]; then
    MERGED_TXT="${OUTDIR}/${STEM}__merged.txt"
    cat "$PREV_TXT" "$TXT_OUT" > "$MERGED_TXT"
    TXT_OUT="$MERGED_TXT"
  fi
fi

if [[ -z "${TXT_OUT:-}" || ! -f "$TXT_OUT" ]]; then
  # fallback to progress file for MakeNotulen
  if [[ -f "$WHISPER_PROGRESS" ]]; then
    TXT_OUT="$WHISPER_PROGRESS"
  else
    echo "Error: file .txt hasil whisper tidak ditemukan."
    exit 1
  fi
fi

# remove temp wav if not kept
if [[ "$MAKE_NOTULEN_ONLY" != "yes" && "$MAKE_NOTULEN_FROM_PARTS" != "yes" ]]; then
  if [[ "$KEEP_TEMP" != "yes" ]]; then
    rm -f "$PRE_WAV"
  fi
fi

# =========================
# 3) Generate notulensi (optional)
# =========================
NOTULEN_MD="${OUTDIR}/NOTULENSI.md"
RTL_CSV="${OUTDIR}/RTL.csv"

if [[ "$TRANSCRIBE_ONLY" != "yes" ]]; then
  echo "[3/3] Generate NOTULENSI (AI if OPENAI_API_KEY set, else template)..."
fi

if [[ "$TRANSCRIBE_ONLY" != "yes" && -n "${OPENAI_API_KEY:-}" ]]; then
  # Create a tiny venv (local) to avoid PEP668 issues
  VENV_DIR="${OUTDIR}/.venv_notulen"
  if [[ ! -d "$VENV_DIR" ]]; then
    python3 -m venv "$VENV_DIR"
  fi
  # shellcheck disable=SC1091
  source "${VENV_DIR}/bin/activate"
  pip -q install -U pip
  pip -q install openai

  OPENAI_MODEL="${OPENAI_MODEL:-gpt-5-mini}"

  python3 - <<PY
import os, csv, textwrap
from openai import OpenAI

meeting = os.environ.get("MEETING_NAME", "$MEETING_NAME")
txt_path = "$TXT_OUT"
out_md = "$NOTULEN_MD"
out_csv = "$RTL_CSV"
model = os.environ.get("OPENAI_MODEL", "$OPENAI_MODEL")

with open(txt_path, "r", encoding="utf-8", errors="ignore") as f:
    transcript = f.read()

# Guard: avoid sending extremely huge transcript in one go
# If too large, truncate tail (usually repetitive) - you can adjust as needed.
MAX_CHARS = 120_000
if len(transcript) > MAX_CHARS:
    transcript = transcript[:MAX_CHARS] + "\n\n[TRUNCATED]\n"

client = OpenAI()

instructions = f"""
Kamu adalah notulis profesional untuk rapat pemerintahan (gaya Pemprov).
Buat NOTULENSI berbahasa Indonesia yang rapi, berbasis transkrip.

Outputkan 2 bagian:
(1) Markdown NOTULENSI dengan struktur:
- Judul Rapat
- Waktu/Tanggal (jika tidak ada di transkrip, tulis: "Tidak disebutkan di rekaman")
- Peserta (jika tidak jelas, tulis "Tidak disebutkan lengkap")
- Ringkasan Pembahasan (bullet, 8–15 poin)
- Keputusan (bullet, tegas, 3–10 poin)
- Isu/Risiko yang Muncul (bullet)
- RTL (tabel: No | Tindak Lanjut | PIC | Due Date | Keterangan)

(2) Data RTL dalam format CSV (kolom: No,Tindak Lanjut,PIC,Due Date,Keterangan)

Catatan:
- Jangan mengarang nama orang. Jika PIC tidak jelas, isi "TBD".
- Due Date jika tidak disebutkan: "TBD".
- Tindak lanjut harus actionable, singkat, jelas.
"""

input_text = f"Judul rapat: {meeting}\n\nTRANSKRIP:\n{transcript}"

resp = client.responses.create(
    model=model,
    reasoning={"effort":"low"},
    input=[{"role":"system","content":instructions},
           {"role":"user","content":input_text}],
)

# Extract text
out_text = ""
for item in resp.output:
    if getattr(item, "type", None) == "message":
        for c in item.content:
            if getattr(c, "type", None) == "output_text":
                out_text += c.text

# Split markdown and csv if model returns both; fallback: parse markers
md = out_text
csv_rows = []

# Try to find a CSV block
if "No,Tindak Lanjut,PIC,Due Date,Keterangan" in out_text:
    parts = out_text.split("No,Tindak Lanjut,PIC,Due Date,Keterangan", 1)
    md = parts[0].rstrip()
    csv_body = "No,Tindak Lanjut,PIC,Due Date,Keterangan" + parts[1]
    # Clean potential code fences
    csv_body = csv_body.replace("```csv","").replace("```","").strip()
    lines = [ln.strip() for ln in csv_body.splitlines() if ln.strip()]
    reader = csv.reader(lines)
    csv_rows = list(reader)

# Write NOTULENSI.md
with open(out_md, "w", encoding="utf-8") as f:
    f.write(md.strip() + "\n")

# Write RTL.csv (if extracted), else create minimal placeholder
if csv_rows:
    with open(out_csv, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        for r in csv_rows:
            w.writerow(r)
else:
    with open(out_csv, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["No","Tindak Lanjut","PIC","Due Date","Keterangan"])
        w.writerow(["1","TBD","TBD","TBD","Belum diekstrak otomatis; cek NOTULENSI.md"])

print("OK:", out_md, out_csv)
PY

  deactivate
elif [[ "$TRANSCRIBE_ONLY" != "yes" ]]; then
  # Offline template
  cat > "$NOTULEN_MD" <<EOF
# NOTULENSI RAPAT: ${MEETING_NAME}

- Tanggal: ${TODAY}
- Waktu: Tidak disebutkan di rekaman
- Peserta: Tidak disebutkan lengkap
- Lokasi/Media: (Zoom/Offline) TBD

## Ringkasan Pembahasan
- (Isi ringkasan dari transkrip: ${TXT_OUT})

## Keputusan
- TBD

## Isu/Risiko yang Muncul
- TBD

## RTL
| No | Tindak Lanjut | PIC | Due Date | Keterangan |
|---:|---|---|---|---|
| 1 | TBD | TBD | TBD | TBD |
EOF

  cat > "$RTL_CSV" <<EOF
No,Tindak Lanjut,PIC,Due Date,Keterangan
1,TBD,TBD,TBD,TBD
EOF
fi

echo "========================================"
echo "SELESAI ✅"
echo "Folder: $OUTDIR"
echo "- Transkrip: $TXT_OUT"
echo "- Progress : $WHISPER_PROGRESS"
if [[ "$TRANSCRIBE_ONLY" != "yes" ]]; then
  echo "- Notulensi: $NOTULEN_MD"
  echo "- RTL CSV  : $RTL_CSV"
fi
echo "========================================"
