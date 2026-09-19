FROM debian:bookworm-slim

# Set ENV variables
ENV \
 DEBIAN_FRONTEND="noninteractive" \
 COMPOSER_VERSION="2.8.2" \
 COMPOSER_ALLOW_SUPERUSER=1 \
 COMPOSER_MEMORY_LIMIT="4G" \
 NVM_VERSION="v0.39.7" \
 NPM_VERSION="v20.11.1" \
 NVM_DIR="$HOME/.nvm" \
 ROOT_DIR="/opt/atlassian/pipelines/agent/build" \
 DOCROOT="/opt/atlassian/pipelines/agent/build/docroot" \
 PHP_INI_DIR="/usr/local/etc/php/conf.d/" \
 XDG_RUNTIME_DIR="/tmp" \
 RUNLEVEL=3 \
 TERM='dumb' \
 MYSQL_PASS="Master&passW993" \
 CYPRESS_CACHE_FOLDER="~/.cache/Cypress" \
 CYPRESS_DRUPAL_BASE_URL="http://localhost" \
 CYPRESS_BASE_URL="http://localhost"

WORKDIR /src
# Chromium packages.
RUN apt update >/dev/null; \
    apt install -y chromium xvfb libgtk-3-0 libgconf-2-4 libnss3 libxss1 libxtst6 xauth xvfb fonts-liberation udev libvulkan1; \
    # Cleanup
    apt clean; rm -rf /var/lib/apt/lists/*;

# Bunch of tools we need.
RUN apt update >/dev/null; \
    apt install -y --no-install-recommends npm git git-lfs dnsutils webp rsync curl less ssh-client supervisor unzip zip html2text  \
     mc lsb-release msmtp cron pv patch gettext python3 python3-pip python3-selenium libgd3 jq yq daemon apt-transport-https gnupg locales wget; \
    # Cleanup
    apt clean; rm -rf /var/lib/apt/lists/*;

# Install PHP 8.3 repo
RUN curl -sSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb; \
    dpkg -i /tmp/debsuryorg-archive-keyring.deb; \
    echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list; \
    apt update; \
    apt clean; rm -rf /var/lib/apt/lists/*; rm -rf /tmp/deb*;

# PHP/Apache/MariaDB packages
RUN apt update; apt install -y libapache2-mod-php8.3 mariadb-client apache2 php8.3-cli php8.3-imagick php8.3-apcu php8.3-common php8.3-curl php8.3-gd php8.3-mbstring php8.3-mysql php8.3-opcache php8.3-readline php8.3-sqlite3 php8.3-xml php8.3-zip php8.3-tokenizer php8.3-xml php8.3-zip; \
    # Cleanup
    apt clean; rm -rf /var/lib/apt/lists/*; rm -rf /tmp/deb*; \
    # Apache/PHP settings
    a2enmod headers rewrite deflate php8.3;

# Install Composer 2.
RUN curl -fsSL "https://github.com/composer/composer/releases/download/${COMPOSER_VERSION}/composer.phar" -o /bin/composer; \
    chmod +x /bin/composer; \
    composer global config allow-plugins.dealerdirect/phpcodesniffer-composer-installer true; \
    # Cleanup.
    composer clear-cache;

# Copy PHP and Apache config.
COPY .ci/docker-image/conf/apache-vhost.conf "/etc/apache2/sites-enabled/000-default.conf"
COPY .ci/docker-image/conf/php.ini "${PHP_INI_DIR}/99-sitefarm.ini"
# Copy all command files.
COPY .ci/docker-image/commands/* /bin/
COPY .ci/run/cypress /bin/sf_cypress

RUN set -xe; \
  # Set Locales
	localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8; \
  # Python symlinks
  ln -s /usr/bin/python3 /usr/bin/python;  \
  ln -s /usr/bin/python3 /usr/bin/python2; \
  mkdir -p $ROOT_DIR;  \
  # Make our commands executeable.
  chmod u+x /bin/sf_*;

ENV LC_ALL='en_US.UTF8'
