# ---- Stage 1: build the static site with the Angular CLI (needs Node.js) ----
FROM node:22-alpine AS build
WORKDIR /app
ENV NG_CLI_ANALYTICS=false
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

# ---- Stage 2: serve the result with nginx (Node and Angular CLI are not in the final image) ----
FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
# Angular's "application" builder writes the browser files to dist/browser/
COPY --from=build /app/dist/browser /usr/share/nginx/html
EXPOSE 80
