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
# Use Railway's PORT or default to 80
REAL_PORT=${PORT:-80}
echo "Configuring Apache to listen on port $REAL_PORT"
sed -i "s/Listen 80/Listen $REAL_PORT/g" /etc/apache2/ports.conf
sed -i "s/<VirtualHost \*:80>/<VirtualHost \*:$REAL_PORT>/g" /etc/apache2/sites-available/000-default.conf

# Set ServerName to avoid warnings and potential redirect issues
if [ -n "$PS_DOMAIN" ]; then
    echo "ServerName $PS_DOMAIN" > /etc/apache2/conf-available/servername.conf
    a2enconf servername
fi

# Force HTTPS detection from Railway's Reverse Proxy
echo "SetEnvIf X-Forwarded-Proto https HTTPS=on" > /etc/apache2/conf-available/proxy-https.conf
a2enconf proxy-https

# Configure Trusted Proxies for Railway (standard for reverse proxies)
if [ -n "$PS_TRUSTED_PROXIES" ]; then
    echo "Configuring trusted proxies: $PS_TRUSTED_PROXIES"
else
    # Default to common Railway/Docker proxy ranges if not set
    export PS_TRUSTED_PROXIES="10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
fi

# Update Shop Domain in Database if PS_DOMAIN is set and app is installed
if [ -n "$PS_DOMAIN" ] && [ -f ./app/config/parameters.php ]; then
    echo "Updating PrestaShop domain to: $PS_DOMAIN"
    # We run this in the background after a short delay to ensure DB is ready and Apache is starting
    (
        sleep 30
        php bin/console prestashop:config set PS_SHOP_DOMAIN --value="$PS_DOMAIN" || true
        php bin/console prestashop:config set PS_SHOP_DOMAIN_SSL --value="$PS_DOMAIN" || true
        # Update shop_url table directly as well for the main shop
        mysql -h "$DB_SERVER" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWD" "$DB_NAME" -e "UPDATE ps_shop_url SET domain='$PS_DOMAIN', domain_ssl='$PS_DOMAIN' WHERE id_shop=1;" || true
        echo "Domain update completed."
    ) &
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
