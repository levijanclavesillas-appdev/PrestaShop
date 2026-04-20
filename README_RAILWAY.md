# PrestaShop Railway Deployment Guide

This project is configured for deployment on [Railway](https://railway.app/).

## Prerequisites

1. A Railway account.
2. A MySQL/MariaDB service added to your Railway project.

## Configuration

The deployment uses a custom `Dockerfile` and `railway.json` to handle the build and runtime environment.

### Environment Variables

The following environment variables should be configured in your Railway service settings. Most `DB_*` variables will be automatically mapped from Railway's MySQL service if you link it.

| Variable | Description | Default |
|----------|-------------|---------|
| `PS_DOMAIN` | Your deployment domain (e.g., `myapp.up.railway.app`) | `localhost` |
| `ADMIN_MAIL` | Email for the admin account | `admin@example.com` |
| `ADMIN_PASSWD` | Password for the admin account | `password123` |
| `PS_INSTALL_AUTO` | Set to `1` to automatically install PrestaShop | `1` |
| `PS_LANGUAGE` | Default language (e.g., `en`) | `en` |
| `PS_COUNTRY` | Default country (e.g., `us`) | `us` |

**Database Variables (Automatically mapped if MySQL service is linked):**
- `DB_SERVER` (mapped from `MYSQLHOST`)
- `DB_USER` (mapped from `MYSQLUSER`)
- `DB_PASSWD` (mapped from `MYSQLPASSWORD`)
- `DB_NAME` (mapped from `MYSQLDATABASE`)
- `DB_PORT` (mapped from `MYSQLPORT`)

### Persistence (Railway Volumes)

PrestaShop writes to the filesystem for images, modules, and configurations. To prevent data loss on redeployment, you **MUST** set up Railway Volumes for the following paths:

1. `/var/www/html/img` - Product and category images.
2. `/var/www/html/modules` - Installed modules.
3. `/var/www/html/themes` - Themes (if you modify them via BO).
4. `/var/www/html/upload` - Uploaded files.
5. `/var/www/html/download` - Downloadable products.
6. `/var/www/html/config` - PrestaShop configuration files (specifically `settings.inc.php`).
7. `/var/www/html/mails` - Email templates.
8. `/var/www/html/translations` - Translation files.

*Note: Railway currently supports one volume per service. You may need to mount a single volume to a parent path if possible, or use a cloud storage module (like S3) for images.*

## Deployment Steps

1. Push your code to GitHub.
2. Create a new service on Railway from your GitHub repository.
3. Railway will detect the `Dockerfile` and `railway.json`.
4. Add a MySQL service to the same project.
5. Link the MySQL service to your PrestaShop service.
6. Set the `PS_DOMAIN` environment variable to your Railway public domain.
7. Deploy!

## Troubleshooting

- **Installation Loop**: If PrestaShop keeps trying to install, check if the `config/settings.inc.php` file is being persisted correctly.
- **Port Issues**: The custom entrypoint script handles port binding for Railway's `$PORT` environment variable.
- **Memory Limit**: PrestaShop build process (composer/npm) can be memory-intensive. Ensure your Railway build plan has at least 2GB of RAM.
