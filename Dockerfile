# MInfy Spielserver als Docker-Container (Linux, x86_64)
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.4.1
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates wget unzip libfontconfig1 \
 && rm -rf /var/lib/apt/lists/* \
 && wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" -O /tmp/godot.zip \
 && unzip -q /tmp/godot.zip -d /tmp/godot \
 && mv /tmp/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
 && rm -rf /tmp/godot /tmp/godot.zip

WORKDIR /game
COPY project.godot main.tscn ./
COPY scripts ./scripts

# Spielstände liegen hier (als Volume gemountet, damit sie Updates überleben)
VOLUME ["/root/.local/share/godot/app_userdata/MInfy"]
EXPOSE 7777/udp

CMD ["godot", "--headless", "--xr-mode", "off", "--path", "/game", "--", "--server", "--port=7777"]
