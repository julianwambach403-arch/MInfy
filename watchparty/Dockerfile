# MInfy Lounge als Docker-Container
FROM node:22-slim
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY server.js ./
COPY public ./public
# Selbst erstelltes Zertifikat bleibt erhalten (sonst müsste man die Warnung immer neu bestätigen)
VOLUME ["/app/certs"]
EXPOSE 8443
CMD ["node", "server.js"]
