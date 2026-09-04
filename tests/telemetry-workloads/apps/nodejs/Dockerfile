FROM node:22.16.0-bookworm-slim
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev --ignore-scripts=false
COPY server.js ./
USER node
EXPOSE 8080
CMD ["node", "server.js"]
