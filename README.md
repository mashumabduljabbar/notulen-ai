# Cara Menjalankan Aplikasi Notulensi Otomatis (Audio → Teks → Notulen)

Dokumen ini menjelaskan langkah **menjalankan aplikasi notulensi otomatis** yang:
- melakukan **pre-processing audio**
- transkripsi **Whisper (Bahasa Indonesia)**
- otomatis membuat **Notulensi (Ringkasan + Keputusan + RTL)**
- **auto folder** per tanggal dan nama rapat

Dokumen ini difokuskan pada **cara menjalankan** dan **pengaturan API Key + Model AI**.

---

## 1. Prasyarat Sistem
Pastikan aplikasi berikut sudah terpasang di Linux:

```bash
sudo apt update
sudo apt install -y ffmpeg pipx python3-venv
```

Pastikan Whisper sudah terpasang via pipx:
```bash
pipx install openai-whisper
```

---

## 2. Menjalankan Aplikasi (WAJIB SET API KEY & MODEL)

Aplikasi **selalu direkomendasikan dijalankan dengan AI aktif** agar:
- ringkasan pembahasan otomatis
- keputusan rapat terstruktur
- RTL langsung siap dipantau

### 2.1 Set API Key OpenAI (WAJIB)

Sebelum menjalankan aplikasi, **set API Key terlebih dahulu**:

```bash
export OPENAI_API_KEY="ISI_API_KEY_ANDA"
```

Agar permanen (tidak perlu set ulang setiap buka terminal):
```bash
echo 'export OPENAI_API_KEY="ISI_API_KEY_ANDA"' >> ~/.bashrc
source ~/.bashrc
```

---

### 2.2 Pilih Model AI (Disarankan)

Gunakan **model yang seimbang kualitas & biaya**:

```bash
export OPENAI_MODEL="gpt-5-mini"
```

Alasan:
- kualitas ringkasan rapat sangat baik
- cepat
- stabil untuk dokumen panjang (transkrip)

Jika tidak diset, aplikasi otomatis menggunakan:
```
gpt-5-mini
```

---

## 2.3 Pilih Model Whisper (small/medium/large)

Model Whisper menentukan kualitas dan kecepatan transkripsi.
Default di script: `medium`.

Contoh mengganti model:
```bash
./notulen.sh -m small "Rapat Koordinasi Carik" rapat.wav
```

Patokan umum:
- `small`: lebih cepat, akurasi lebih rendah
- `medium`: seimbang (default)
- `large`: akurasi tertinggi, paling lambat

---

## 3. Menjalankan Script Notulensi

Format perintah:

```bash
./notulen.sh "NAMA RAPAT" file_audio
```

### Mode transkrip saja (disarankan untuk file part)
Gunakan `-t` agar hanya transkripsi (skip `NOTULENSI.md` + `RTL.csv`):
```bash
./notulen.sh -m small -d cpu -t "Transkrip 2026-02-10 part 000" 2026-02-10_part_000.flac
```

### Contoh standar (transkrip + notulen template/AI):
```bash
./notulen.sh "Rapat Koordinasi Kader Dasawisma" rapat.wav
```

### Contoh lengkap (sekali jalan):
```bash
OPENAI_API_KEY=sk-xxxxx OPENAI_MODEL=gpt-5-mini ./notulen.sh "FGD Tata Kelola DTSEN" rekaman_fgd.mp3
```

### Buat notulen ulang dari folder rapat terbaru (tanpa transkrip ulang):
```bash
./notulen.sh "Nama Rapat" MakeNotulen
```

### Gabung hasil transkrip part lalu buat notulen AI:
```bash
./notulen.sh "Nama Rapat Final" MakeNotulenFromParts 2026-02-13 2026-02-10
```
Keterangan:
- `2026-02-13` = tanggal folder output transkrip part di `notulen/`
- `2026-02-10` = prefix part (`2026-02-10_part_000.flac`, dst)
- `part_prefix` akan dicoba dalam bentuk raw dan slug (contoh: `"2026-02-13 DILAN"` juga cocok ke folder `transkrip_2026-02-13_dilan_part_*`)

---

## 4. Struktur Output Otomatis

Setiap eksekusi membuat folder:

```
notulen/
└── YYYY-MM-DD/
    └── nama_rapat/
        ├── rekaman_asli.ext                 # jika mode audio biasa (bukan MakeNotulen)
        ├── *_whisper.progress.txt           # progress realtime
        ├── *.txt / *.srt / *.vtt / *.tsv    # output whisper
        ├── whisper.log
        ├── NOTULENSI.md                     # jika tidak pakai -t
        └── RTL.csv                          # jika tidak pakai -t
```

Pada mode `MakeNotulenFromParts`, folder rapat final akan berisi:
- `combined__whisper.progress.txt` (gabungan transkrip part)
- `NOTULENSI.md`
- `RTL.csv`

### File utama:
- **NOTULENSI.md** → siap disalin ke Word / Nota Dinas
- **RTL.csv** → siap dipantau di Excel

---

## 5. Cara Mendapatkan API Key OpenAI

Ikuti langkah berikut:

### 5.1 Buka Website Resmi
Buka:
```
https://platform.openai.com/
```

Login menggunakan:
- akun Google, atau
- email kantor/pribadi

---

### 5.2 Masuk ke Dashboard API
Setelah login:
1. Klik **Profile / Settings**
2. Pilih menu **API Keys**
3. Klik **Create new secret key**

---

### 5.3 Simpan API Key
- Salin API Key yang muncul (contoh: `sk-xxxx`)
- **Simpan di tempat aman**
- Jangan dibagikan di grup / publik

> Catatan: API Key **hanya muncul sekali**

---

## 6. Catatan Keamanan & Privasi

- Transkrip rapat akan dikirim ke API **hanya untuk proses peringkasan**
- Tidak digunakan untuk training model
- Jika rapat sangat sensitif, aplikasi masih bisa dijalankan **tanpa API Key** (mode template)

---

## 7. Troubleshooting Singkat

### Whisper tidak dikenali:
```bash
pipx run openai-whisper --help
```

### Audio kurang jelas:
```bash
ffmpeg -i rapat.wav -ar 16000 -ac 1 rapat_bersih.wav
```

---

## 7.1 Cek GPU & Pakai GPU untuk Whisper

### Cara cek GPU
NVIDIA:
```bash
nvidia-smi
```

Cek deteksi perangkat grafis:
```bash
lspci | grep -i -E "vga|3d|nvidia|amd|radeon"
```

AMD (ROCm, jika terpasang):
```bash
rocm-smi
```

Jika perintah di atas tidak menampilkan GPU, berarti sistem belum mengenali GPU atau driver belum terpasang.

### Cara menggunakan GPU
Whisper bisa memakai GPU dengan `--device cuda` dan `--fp16 True`.

Catatan: script `notulen.sh` default `auto` (coba GPU dulu, jika tidak tersedia otomatis fallback ke CPU).
```bash
./notulen.sh -d auto -f True "Rapat ..." audio.wav
./notulen.sh -d cpu "Rapat ..." audio.wav
./notulen.sh -d cuda -f True "Rapat ..." audio.wav
```

Contoh perintah Whisper langsung:
```bash
whisper audio.wav --model medium --language Indonesian --device cuda --fp16 True
```

### Catatan khusus AMD (ROCm)
Untuk GPU AMD di Linux, Whisper via PyTorch perlu **ROCm + PyTorch ROCm** agar bisa pakai GPU.
Jika ROCm belum terpasang, `--device cuda` akan gagal atau tetap pakai CPU.

Langkah umum (ringkas):
1. Pastikan GPU AMD kamu didukung ROCm (cek di dokumentasi AMD).
2. Install ROCm sesuai OS kamu (dokumentasi AMD).
3. Install PyTorch ROCm, misalnya:
```bash
pip install --index-url https://download.pytorch.org/whl/rocm6.1 torch torchvision torchaudio
```
Sesuaikan versi ROCm dengan yang kamu install.

Cara cek PyTorch mendeteksi GPU:
```bash
python3 - <<'PY'
import torch
print("cuda available:", torch.cuda.is_available())
print("cuda device:", torch.cuda.get_device_name(0) if torch.cuda.is_available() else "none")
PY
```

Jika hasilnya `cuda available: False`, berarti masih CPU.

---

## 7.2 Transcribe Mulai Menit Tertentu

Jika ingin melanjutkan transkrip dari menit tertentu, potong audio dengan `ffmpeg`, lalu jalankan `notulen.sh` pada file hasil potongan.

Contoh mulai dari menit 47:
```bash
ffmpeg -ss 00:47:00 -i 2026-02-10.flac -c copy 2026-02-10_part2.flac
./notulen.sh -m medium -d cuda -f True "01-Rapat-DILAN (lanjutan)" 2026-02-10_part2.flac
```

Catatan:
- File potongan hanya berisi bagian setelah menit tersebut.
- NOTULENSI yang dibuat hanya untuk bagian itu (bukan otomatis gabungan).

---

## 7.3 Setup GPU AMD (ROCm) untuk Whisper

GPU AMD **tidak otomatis dipakai** tanpa ROCm + PyTorch ROCm yang sesuai.
Ikuti langkah berikut (ringkas):

1. Pastikan OS kamu **didukung ROCm** (cek daftar OS di dokumentasi AMD).
2. Install ROCm sesuai panduan resmi AMD (Radeon/Ryzen untuk iGPU/APU).
3. Install PyTorch ROCm sesuai versi ROCm yang dipasang.
4. Verifikasi PyTorch mendeteksi GPU.
5. Jalankan `notulen.sh` dengan `-d auto` atau `-d cuda`.

Link resmi (salin ke browser):
```text
https://rocm.docs.amd.com/projects/install-on-linux/en/latest/reference/system-requirements.html
https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installrad/native_linux/install-pytorch.html
https://pytorch.org/get-started/locally/
```

Catatan:
- AMD merekomendasikan **ROCm WHLs dari repo.radeon.com** (lihat panduan PyTorch ROCm AMD).
- Alternatifnya, gunakan **matrix resmi PyTorch** (Linux + pip + ROCm) untuk perintah yang sesuai.

Cek GPU terdeteksi oleh PyTorch:
```bash
python3 - <<'PY'
import torch
print("cuda available:", torch.cuda.is_available())
print("cuda device:", torch.cuda.get_device_name(0) if torch.cuda.is_available() else "none")
PY
```

Catatan penting dukungan OS/GPU:
- ROCm untuk **Ryzen/APU** fokus pada distro tertentu (misalnya Ubuntu LTS tertentu).
- **Debian/Parrot** umumnya **tidak didukung resmi** untuk Radeon/Ryzen iGPU.
- Jika OS/GPU kamu tidak masuk daftar kompatibel, PyTorch kemungkinan **tidak akan melihat GPU**.

Jalankan dengan auto GPU:
```bash
./notulen.sh -d auto -f True "Rapat ..." audio.wav
```

### Best‑effort di Parrot/Debian (tanpa dukungan resmi)
AMD merekomendasikan jalur **Docker** untuk mengurangi masalah instalasi ROCm di host. Jika ingin mencoba:
```bash
docker pull rocm/pytorch:latest
docker run -it \
  --device=/dev/kfd --device=/dev/dri --group-add video \
  --ipc=host --shm-size 8G \
  -v "$PWD":/work \
  rocm/pytorch:latest
```

Di dalam container, install Whisper dan jalankan transkrip:
```bash
pip install openai-whisper
whisper /work/2026-02-10.flac --model small --language Indonesian --device cuda --fp16 True
```

Catatan:
- ROCm wheels sering mensyaratkan **Python 3.12** (cek catatan AMD).
- Jika `/dev/kfd` tidak ada, ROCm tidak aktif di host dan GPU tidak akan terbaca di container.

---

## 7.4 Resume Otomatis & Mode MakeNotulen

### Resume otomatis (lanjut dari menit terakhir)
Jika proses transcribe terhenti, script akan:
- membaca timestamp terakhir di `__whisper.progress.txt`
- memotong audio dari titik tersebut
- melanjutkan transkrip dan **menambahkan hasilnya** ke file progress yang sama

Dengan begitu, kamu tidak perlu potong manual.

### Buat notulen saja (tanpa transcribe ulang)
Jika transkrip sudah ada, kamu bisa membuat notulen ulang dengan:
```bash
./notulen.sh "Nama Rapat" MakeNotulen
```
Script akan mencari folder rapat yang **terbaru** dan membaca `__whisper.progress.txt` sebagai sumber.

### Gabung hasil transkrip part lalu buat notulen
Jika kamu transkrip per part (satu-satu), jalankan:
```bash
./notulen.sh "Nama Rapat Final" MakeNotulenFromParts 2026-02-13 2026-02-10
```
Script akan:
- mencari folder part dengan pola `notulen/2026-02-13/transkrip_2026-02-10_part_*` (raw + slug)
- menggabungkan transkrip `.txt` yang tersedia
- menyimpan gabungan ke `combined__whisper.progress.txt`
- membuat `NOTULENSI.md` + `RTL.csv` dari gabungan tersebut

---

## 8. Rekomendasi Pemakaian

Aplikasi ini cocok dijadikan:
- **SOP Notulensi Rapat OPD**
- Pendukung **SPBE & arsip digital**
- Standar dokumentasi FGD / konsultasi publik

---

**Catatan Akhir**  
Dokumen ini dapat dilampirkan sebagai **panduan operasional resmi** atau **manual pengguna internal**.
