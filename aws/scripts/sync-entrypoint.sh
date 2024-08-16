#!/usr/bin/env sh
# set -eo pipefail
set -x

mkdir -p /etc/nginx/sites-enabled
mkdir -p /etc/nginx/sites-available

cp -r ./nginx.conf /etc/nginx/nginx.conf
cp -r ./default.conf /etc/nginx/sites-enabled/default.conf

ln -s /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default || echo "Link to default nginx conf already exists"

adduser -S www-data

nginx
./strfry sync wss://purplerelay.com --dir both
./strfry router /etc/strfry-router.config