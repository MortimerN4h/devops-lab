FROM node:22-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev
COPY . .
# The node image ships a non-root user "node" (uid 1000). Files above stay owned by root = read-only for the app.
USER node
EXPOSE 3000
CMD ["node", "server.js"]
