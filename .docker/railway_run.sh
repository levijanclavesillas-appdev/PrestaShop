#!/bin/bash
set -e

# Map Railway MySQL variables to PrestaShop variables if they exist
export DB_USER=${DB_USER:-$MYSQLUSER}
export DB_PASSWD=${DB_PASSWD:-$MYSQLPASSWORD}
export DB_SERVER=${DB_SERVER:-$MYSQLHOST}
export DB_PORT=${DB_PORT:-$MYSQLPORT}
export DB_NAME=${DB_NAME:-$MYSQLDATABASE}

# Fix Apache MPM conflict at runtime
a2dismod mpm_event mpm_worker || true
a2enmod mpm_prefork || true

# Railway provides the PORT environment variable.
# Apache by default is configured to listen on port 80.
if [ -n "$PORT" ]; then
    echo "Configuring Apache to listen on port $PORT"
    sed -i "s/Listen 80/Listen $PORT/g" /etc/apache2/ports.conf
    sed -i "s/<VirtualHost \*:80>/<VirtualHost \*:$PORT>/g" /etc/apache2/sites-available/000-default.conf
fi

# PrestaShop official image uses /tmp/docker_run.sh as its entrypoint logic.
# It handles installation if DB_* variables are provided and PS_INSTALL_AUTO=1.
if [ -f /tmp/docker_run.sh ]; then
    # We need to make sure the script is executable
    chmod +x /tmp/docker_run.sh
    exec /tmp/docker_run.sh
else
    echo "Warning: /tmp/docker_run.sh not found, starting apache directly."
    exec apache2-foreground
fi
