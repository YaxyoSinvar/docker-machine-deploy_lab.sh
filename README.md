## To'liq avtomatlashtirilgan script (`deploy_lab.sh`)

## Manual Control

## Yagona skript bilan to'liq deploy qilish:

Agar siz hamma narsani bitta fayldan ishga tushirmoqchi bo'lsangiz, yuqoridagi `deploy_lab.sh` faylini yarating va ishga tushiring. Bu skript:

1. **Avtomatik** barcha kerakli fayl va papkalarni yaratadi
2. **Docker** va docker-compose ni tekshiradi
3. **Flag** larni yaratadi
4. **Container** larni build qiladi
5. **Tarmoq** ni sozlaydi
6. **Barcha servislarni** ishga tushiradi
7. **Ctrl+C** bosilganda to'liq tozalaydi

## Tekshirish uchun:

```bash
# Containerlar ishlayaptimi?
docker ps

# Web app ga kirish
curl <http://localhost:8080>

# Linux mashinasiga SSH
ssh user1@localhost -p 2222

# Flags ni o'qish
curl <http://localhost:8080/flag1>
```

## Muhim jihatlar:

1. **Hech qanday o'zgartirish** asosiy tizimga saqlanmaydi
2. **To'liq izolyatsiya** - Docker network ichida
3. **Avtomatik tozalash** - Ctrl+C bosilganda hamma narsa o'chadi
4. **Realistic vulnerabilities** - Haqiqiy CVE'lar asosida
5. **Multiple attack paths** - Turli xil hujum vektorlari
