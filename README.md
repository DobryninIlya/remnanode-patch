# remnanode-patch

Скрипт для автоматической настройки путей к TLS-сертификатам на нодах [Remnawave](https://remnawave.dev) VPN.

## Проблема

Remnanode и nginx по умолчанию используют захардкоженный домен в путях к сертификатам внутри `docker-compose.yml` и `nginx.conf`. Это означает что для каждой ноды нужно вручную менять конфиг.

Скрипт решает это один раз: монтирует сертификаты в фиксированный путь `/etc/xray/certs/` через переменную `XRAY_DOMAIN`, после чего конфиг профиля в панели становится **универсальным для всех нод**.

## Что делает скрипт

- Авто-определяет домен из `/etc/letsencrypt/live/`
- Добавляет `XRAY_DOMAIN` в `.env`
- Добавляет volume-маунты в `docker-compose.yml` для remnanode → `/etc/xray/certs/`
- Создаёт бэкап `docker-compose.yml.bak` перед изменением
- Идемпотентен — безопасно запускать повторно

## Установка (одна команда)

```bash
curl -fsSL https://raw.githubusercontent.com/DobryninIlya/remnanode-patch/main/patch-remnanode.sh | bash
```

## Использование

```bash
# Скачать и запустить
curl -fsSL https://raw.githubusercontent.com/DobryninIlya/remnanode-patch/main/patch-remnanode.sh -o patch-remnanode.sh
chmod +x patch-remnanode.sh
bash patch-remnanode.sh
```

## После запуска

Обнови конфиг профиля в панели Remnawave — замени пути к сертификатам на фиксированные:

```json
"certificates": [
  {
    "keyFile": "/etc/xray/certs/privkey.pem",
    "certificateFile": "/etc/xray/certs/fullchain.pem"
  }
]
```

Убери или оставь пустым поле `serverName` — xray автоматически возьмёт его из SNI клиента.

## Требования

- Ubuntu/Debian
- Docker + Docker Compose
- Certbot (сертификат уже должен быть получен)
- Remnanode установлен в `/opt/remnanode/`

## Структура после патча

```
/opt/remnanode/
├── docker-compose.yml   # добавлены volume-маунты для /etc/xray/certs/
├── docker-compose.yml.bak  # бэкап оригинала
└── .env                 # добавлена переменная XRAY_DOMAIN=<домен>
```

Внутри remnanode контейнера сертификаты доступны по:
```
/etc/xray/certs/fullchain.pem
/etc/xray/certs/privkey.pem
```
