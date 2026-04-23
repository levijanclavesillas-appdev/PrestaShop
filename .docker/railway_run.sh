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

# Increase PHP upload limits for modules
echo "upload_max_filesize = 128M" > /usr/local/etc/php/conf.d/uploads.ini
echo "post_max_size = 128M" >> /usr/local/etc/php/conf.d/uploads.ini
echo "memory_limit = 512M" >> /usr/local/etc/php/conf.d/uploads.ini

# Ensure mod_rewrite is enabled
a2enmod rewrite || true

# Use Railway's PORT or default to 80
REAL_PORT=${PORT:-80}
echo "Configuring Apache to listen on port $REAL_PORT"
sed -i "s/Listen 80/Listen $REAL_PORT/g" /etc/apache2/ports.conf

# Update Apache site config to allow overrides and use correct port
echo "<VirtualHost *:$REAL_PORT>
    DocumentRoot /var/www/html
    <Directory /var/www/html>
        Options +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>" > /etc/apache2/sites-available/000-default.conf

# Enable the site and ensure other configs don't interfere
a2ensite 000-default || true
a2enmod rewrite || true

# Set ServerName globally to avoid warnings and potential redirect issues
if [ -n "$PS_DOMAIN" ]; then
    echo "ServerName $PS_DOMAIN" > /etc/apache2/conf-available/servername.conf
    a2enconf servername
    echo "ServerName $PS_DOMAIN" >> /etc/apache2/apache2.conf
fi

# Ensure permissions at runtime (especially for volumes)
chown -R www-data:www-data /var/www/html/img /var/www/html/themes /var/www/html/modules /var/www/html/var
chmod -R 755 /var/www/html/img /var/www/html/themes

# Force HTTPS detection from Railway's Reverse Proxy
echo "SetEnvIf X-Forwarded-Proto https HTTPS=on" > /etc/apache2/conf-available/proxy-https.conf
a2enconf proxy-https

# Configure Trusted Proxies for Railway (standard for reverse proxies)
if [ -n "$PS_TRUSTED_PROXIES" ]; then
    echo "Configuring trusted proxies: $PS_TRUSTED_PROXIES"
else
    # Default to common Railway/Docker proxy ranges if not set
    export PS_TRUSTED_PROXIES="10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,127.0.0.1"
fi

# Clear PrestaShop/Symfony cache to apply new settings
if [ -f bin/console ]; then
    echo "Clearing cache..."
    php bin/console cache:clear --no-warmup || true
fi

# Update Shop Domain in Database if PS_DOMAIN is set and app is installed
if [ -n "$PS_DOMAIN" ] && [ -f ./app/config/parameters.php ]; then
    echo "Updating PrestaShop domain to: $PS_DOMAIN"
    # We run this in the background after a short delay to ensure DB is ready and Apache is starting
    (
        sleep 30
        php bin/console prestashop:config set PS_SHOP_DOMAIN --value="$PS_DOMAIN" || true
        php bin/console prestashop:config set PS_SHOP_DOMAIN_SSL --value="$PS_DOMAIN" || true
        # Enable Friendly URLs and regenerate .htaccess
        echo "Regenerating Friendly URLs and .htaccess..."
        php bin/console prestashop:config set PS_REWRITING_SETTINGS --value="1" || true
        php -r "require 'config/config.inc.php'; Tools::generateHtaccess();" || true
        # Disable IP check for cookies (essential for proxies/load balancers)
        php bin/console prestashop:config set PS_COOKIE_CHECKIP --value="0" || true
        # Update shop_url table directly as well for the main shop
        mysql -h "$DB_SERVER" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWD" "$DB_NAME" -e "UPDATE ps_shop_url SET domain='$PS_DOMAIN', domain_ssl='$PS_DOMAIN', main=1 WHERE id_shop=1;" || true
        # Restrict countries to Southeast Asia (SEA)
        echo "Restricting countries to SEA (PH, SG, MY, ID, TH, VN, BN, KH, LA, MM, TL)..."
        mysql -h "$DB_SERVER" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWD" "$DB_NAME" -e "UPDATE ps_country SET active=0; UPDATE ps_country SET active=1 WHERE iso_code IN ('PH', 'SG', 'MY', 'ID', 'TH', 'VN', 'BN', 'KH', 'LA', 'MM', 'TL');" || true
        
        # Authorize instapayment for all active countries, currencies, and groups
        echo "Authorizing instapayment and linking carriers..."
        mysql -h "$DB_SERVER" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWD" "$DB_NAME" -e "
            SET @module_id = (SELECT id_module FROM ps_module WHERE name = 'instapayment');
            INSERT IGNORE INTO ps_module_country (id_module, id_shop, id_country) SELECT @module_id, 1, id_country FROM ps_country WHERE active = 1;
            INSERT IGNORE INTO ps_module_currency (id_module, id_shop, id_currency) SELECT @module_id, 1, id_currency FROM ps_currency WHERE active = 1;
            INSERT IGNORE INTO ps_module_group (id_module, id_shop, id_group) SELECT @module_id, 1, id_group FROM ps_group;
            INSERT IGNORE INTO ps_module_carrier (id_module, id_shop, id_reference) SELECT @module_id, 1, id_reference FROM ps_carrier WHERE active = 1 AND deleted = 0;
            
            -- Ensure all active carriers are linked to all zones (fixes missing shipping step)
            INSERT IGNORE INTO ps_carrier_zone (id_carrier, id_zone) 
            SELECT c.id_carrier, z.id_zone FROM ps_carrier c CROSS JOIN ps_zone z WHERE c.active = 1 AND c.deleted = 0 AND z.active = 1;
            
            -- Ensure all active carriers have tax rules (even if 0)
            INSERT IGNORE INTO ps_carrier_tax_rules_group_shop (id_carrier, id_tax_rules_group, id_shop)
            SELECT id_carrier, 0, 1 FROM ps_carrier WHERE active = 1 AND deleted = 0;
        " || true
        
        echo "SEA Country restriction, instapayment authorization, and carrier mapping completed."
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
