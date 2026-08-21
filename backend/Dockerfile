# Local dev image — matches the Node version this project develops against
# (see package.json's "engines"). Not a production/hosting decision; see
# docs/technical/architecture/backend-mvp-plan.md §5 for that.
FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .

EXPOSE 3000

CMD ["npm", "run", "dev"]
