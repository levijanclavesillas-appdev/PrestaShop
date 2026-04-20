# Stage 1: Build assets and dependencies
FROM prestashop/base:8.1-apache AS builder

WORKDIR /var/www/html

# Install Composer
RUN php -r "copy('https://getcomposer.org/installer', '/tmp/composer-setup.php');" && \
    php /tmp/composer-setup.php --no-ansi --install-dir=/usr/local/bin --filename=composer && \
    rm -rf /tmp/composer-setup.php

# Copy only composer and package files first for better caching
COPY composer.json composer.lock ./
# PrestaShop needs some folders to exist for composer plugins
RUN mkdir -p modules themes override

# Install composer dependencies
RUN composer install --no-dev --optimize-autoloader --no-interaction

# Copy the rest of the source code
COPY . .

# Install Node.js and build assets
RUN apt-get update && apt-get install -y curl gnupg && \
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs && \
    ./tools/assets/build.sh all

# Stage 2: Final production image
FROM prestashop/prestashop:8.1-apache

# Copy built files from builder
COPY --from=builder /var/www/html /var/www/html

# Set permissions
RUN chown -R www-data:www-data /var/www/html

# Environment variables for PrestaShop
ENV PS_INSTALL_AUTO=1
ENV PS_DOMAIN=localhost
ENV PS_ENABLE_SSL=0
ENV PS_DEV_MODE=0

# Entrypoint for Railway
COPY .docker/railway_run.sh /usr/local/bin/railway_run.sh
RUN chmod +x /usr/local/bin/railway_run.sh

ENTRYPOINT ["/usr/local/bin/railway_run.sh"]
