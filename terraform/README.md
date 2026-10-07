# Деплой на AWS через Terraform

Одна команда (`terraform apply`) створює сервер в AWS і піднімає на ньому весь стек
(`docker-compose.yml` з цього репо). `terraform destroy` — видаляє все.

## 1. AWS-акаунт

Потрібно: email, номер телефону (SMS/дзвінок з кодом), банківська картка Visa/Mastercard
(блокується ~$1 для перевірки), адреса.

1. https://aws.amazon.com/free → **Create free account**.
2. При виборі плану — **Free account plan**: гроші з картки не списуються, поки сам
   не перейдеш на Paid. Дається $100 кредитів (+ до $100 за завдання в консолі),
   план діє 6 місяців або до вичерпання кредитів.
3. Наш стек коштує ~$20/міс (EC2 `t3.small` ~$15, Elastic IP ~$3.6, диск ~$1.6),
   тобто кредитів вистачає на ~5–6 місяців. `t3.small` входить у Free Tier.

> Коли план закінчиться, без переходу на Paid акаунт закриється разом із сервером і БД —
> заздалегідь зробіть дамп бази.

## 2. Ключі доступу для Terraform

Не працюйте з root-акаунта.

1. Консоль AWS → **IAM** → **Users** → **Create user**, ім'я напр. `terraform`.
2. **Attach policies directly** → `AmazonEC2FullAccess` (усе, що створює Terraform, — це EC2).
3. Відкрити користувача → **Security credentials** → **Create access key** →
   *Command Line Interface (CLI)*. Зберегти `Access key ID` і `Secret access key`
   (secret показується один раз).
4. Передавати ключі лише тому, хто запускатиме деплой, і не через публічні чати.
   Не комітити.

## 3. Підготовка (на машині, з якої деплоїмо)

```bash
brew install hashicorp/tap/terraform awscli
aws configure            # ключі з п.2, region: eu-central-1, output: json
```

У корені `cubic-infra`:

```bash
cp .env.example .env.prod   # заповнити секрети (див. нижче)
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

`.env.prod` — обов'язково змінити:
- `POSTGRES_PASSWORD` і пароль у `DATABASE_URL` (однакові)
- `JWT_SECRET_KEY` — довгий випадковий рядок (`openssl rand -hex 32`)
- `ADMIN_USERNAME` / `ADMIN_PASSWORD` / `ADMIN_EMAIL`
- `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET`
- `GOOGLE_REDIRECT_URI=https://<домен>/auth/callback`
- `CORS_ALLOW_ORIGINS=https://<домен>`

## 4. Деплой

```bash
terraform init
terraform apply          # показує план, підтвердити "yes"
```

В output буде `public_ip` і `url`. Сервер ще ~3–5 хв ставить Docker і качає образи.

## 5. Домен

Домен `cubic-helper-m.pp.ua` зареєстрований на nic.ua, NS — «Сервери імен NIC.UA».

1. nic.ua → домен → **Змінити DNS-записи** → додати запис:
   тип `A`, ім'я `@`, значення — `public_ip` з output.
2. Коли домен почне резолвитись (`dig +short cubic-helper-m.pp.ua`), Caddy сам отримає
   HTTPS-сертифікат.
3. Google Cloud Console → Credentials → OAuth Client:
   - Authorized JavaScript origins: `https://cubic-helper-m.pp.ua`
   - Authorized redirect URIs: `https://cubic-helper-m.pp.ua/auth/callback`

Без домену (`domain` не задано) сайт працює по `http://<ip>`, але вхід через Google — ні;
адмін-логін працює.

## Оновлення та обслуговування

- Нова версія застосунку (після мерджу в `main` CI публікує образи в GHCR):
  ```bash
  ssh ubuntu@<ip>
  cd /opt/cubic-infra && sudo docker compose pull && sudo docker compose up -d
  ```
  Для SSH треба задати `ssh_public_key` у `terraform.tfvars` до `apply`.
- Повторний `terraform apply` не перестворює сервер (БД живе на його диску).
- `terraform.tfstate` містить секрети з `.env.prod` — не комітити, не губити:
  без нього Terraform «забуде» про створені ресурси.
- Видалити все: `terraform destroy`.
