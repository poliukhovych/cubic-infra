# Deploying to AWS with Terraform

One command (`terraform apply`) creates a server in AWS and brings up the whole stack on it
(`docker-compose.yml` from this repo). `terraform destroy` removes everything.

## 1. AWS account

You need: an email, a phone number (verification code via SMS/call), a Visa/Mastercard
(~$1 is held for verification), and an address.

1. https://aws.amazon.com/free → **Create free account**.
2. When choosing a plan, pick the **Free account plan**: the card is not charged until you
   switch to Paid yourself. You get $100 in credits (+ up to $100 for completing tasks in the
   console); the plan lasts 6 months or until the credits run out.
3. Our stack costs ~$20/month (EC2 `t3.small` ~$15, Elastic IP ~$3.6, disk ~$1.6),
   so the credits last ~5–6 months. `t3.small` is included in the Free Tier.

> When the plan ends, unless you switch to Paid, the account is closed together with the
> server and the DB — take a database dump in advance.

## 2. Access keys for Terraform

Don't use the root account.

1. AWS Console → **IAM** → **Users** → **Create user**, name e.g. `terraform`.
2. **Attach policies directly** → `AmazonEC2FullAccess` (everything Terraform creates is EC2).
3. Open the user → **Security credentials** → **Create access key** →
   *Command Line Interface (CLI)*. Save the `Access key ID` and `Secret access key`
   (the secret is shown only once).
4. Share the keys only with whoever runs the deploy, and never via public chats.
   Don't commit them.

## 3. Setup (on the machine you deploy from)

```bash
brew install hashicorp/tap/terraform awscli
aws configure            # keys from step 2, region: eu-central-1, output: json
```

In the `cubic-infra` root:

```bash
cp .env.example .env.prod   # fill in secrets (see below)
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

`.env.prod` — must be changed:
- `POSTGRES_PASSWORD` and the password in `DATABASE_URL` (same value)
- `JWT_SECRET_KEY` — a long random string (`openssl rand -hex 32`)
- `ADMIN_USERNAME` / `ADMIN_PASSWORD` / `ADMIN_EMAIL`
- `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET`
- `GOOGLE_REDIRECT_URI=https://<domain>/auth/callback`
- `CORS_ALLOW_ORIGINS=https://<domain>`

## 4. Deploy

```bash
terraform init
terraform apply          # shows the plan, confirm with "yes"
```

The output contains `public_ip` and `url`. The server then needs ~3–5 min to install Docker and pull the images.

## 5. Domain

The domain `cubic-helper-m.pp.ua` is registered at nic.ua, with NIC.UA name servers.

1. nic.ua → domain → **DNS records** → add a record:
   type `A`, name `@`, value — `public_ip` from the output.
2. Once the domain resolves (`dig +short cubic-helper-m.pp.ua`), Caddy obtains
   an HTTPS certificate automatically.
3. Google Cloud Console → Credentials → OAuth Client:
   - Authorized JavaScript origins: `https://cubic-helper-m.pp.ua`
   - Authorized redirect URIs: `https://cubic-helper-m.pp.ua/auth/callback`

Without a domain (`domain` not set) the site works at `http://<ip>`, but Google sign-in doesn't;
admin login works.

## Updates and maintenance

- New app version (after a merge into `main`, CI publishes images to GHCR):
  ```bash
  ssh ubuntu@<ip>
  cd /opt/cubic-infra && sudo docker compose pull && sudo docker compose up -d
  ```
  SSH requires `ssh_public_key` to be set in `terraform.tfvars` before `apply`.
- Re-running `terraform apply` does not recreate the server (the DB lives on its disk).
- `terraform.tfstate` contains secrets from `.env.prod` — don't commit it, don't lose it:
  without it Terraform "forgets" the resources it created.
- Remove everything: `terraform destroy`.
