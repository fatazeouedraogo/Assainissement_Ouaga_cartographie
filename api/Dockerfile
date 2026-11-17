FROM node:22-slim
WORKDIR /srv
ENV NODE_ENV=production
COPY package*.json ./
RUN npm ci --omit=dev
COPY src ./src
COPY db ./db
COPY scripts ./scripts
RUN mkdir -p uploads
EXPOSE 3000
CMD ["node", "src/server.js"]
