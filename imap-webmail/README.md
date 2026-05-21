# 📧 Multi IMAP Webmail Checker

Website untuk cek email masuk dari beberapa akun IMAP sekaligus.

## Setup

```bash
cd "d:\PROJEK BOT\imap-webmail"
pip install -r requirements.txt
```

## ⚠️ PENTING: Isi Password

Edit `accounts.json` dan isi password:
```json
[
  {
    "id": "emelku",
    "name": "emelku.biz.id",
    "host": "mail.privateemail.com",
    "port": 993,
    "tls": true,
    "username": "admin@emelku.biz.id",
    "password": "ISI_PASSWORD_DISINI",
    "domain": "emelku.biz.id"
  }
]
```

Atau tambah akun via web UI setelah server jalan.

## Jalankan

```bash
python app.py
```

Buka: http://localhost:5000

## Fitur

- 📬 Multi akun IMAP (tambah/hapus via UI)
- 🔍 Filter by TO / FROM / Subject
- 🌐 Search di semua akun sekaligus
- 🔗 Auto-detect verification links
- 📧 Render HTML email (sandboxed)
- ↻ Auto-refresh 10 detik
- 🔌 Test koneksi saat tambah akun
- ⚠️ Error handling yang jelas

## Troubleshooting

| Error | Solusi |
|-------|--------|
| Password kosong | Isi password di accounts.json |
| Connection timeout | Cek firewall, ISP mungkin block port 993 |
| Login gagal | Cek username/password benar |
| DNS error | Cek hostname IMAP benar |
