#!/bin/bash

# Interna DNS som signalerar att du är på jobbet
INTERNAL_DNS=("192.168.101.225" "192.168.101.226" "192.168.101.120")
INTERNAL_NTP="192.168.101.10"
EXTERNAL_NTP="0.arch.pool.ntp.org 1.arch.pool.ntp.org"

# Plocka ut alla nuvarande DNS från resolv.conf
CURRENT_DNS=($(grep ^nameserver /etc/resolv.conf | awk '{print $2}'))

# Flagga för om vi är på jobbet
AT_WORK=false

# Jämför varje aktuell DNS med interna DNS
for dns in "${CURRENT_DNS[@]}"; do
    for internal in "${INTERNAL_DNS[@]}"; do
        if [[ "$dns" == "$internal" ]]; then
            AT_WORK=true
            break 2
        fi
    done
done

# Ändra timesyncd.conf beroende på plats
if $AT_WORK; then
    echo "🟢 Du är på jobbet – växlar till intern NTP: $INTERNAL_NTP"
    sudo sed -i "s/^NTP=.*/NTP=$INTERNAL_NTP/" /etc/systemd/timesyncd.conf
    sudo sed -i "s/^FallbackNTP=.*/FallbackNTP=/" /etc/systemd/timesyncd.conf
else
    echo "🔵 Du är inte på jobbet – växlar till externa NTP-servrar"
    sudo sed -i "s/^NTP=.*/NTP=$EXTERNAL_NTP/" /etc/systemd/timesyncd.conf
    sudo sed -i "s/^FallbackNTP=.*/FallbackNTP=/" /etc/systemd/timesyncd.conf
fi

# Starta om timesyncd
echo "🔁 Startar om systemd-timesyncd..."
sudo systemctl restart systemd-timesyncd

# Visa status
echo "🕒 Nuvarande status:"
timedatectl status
