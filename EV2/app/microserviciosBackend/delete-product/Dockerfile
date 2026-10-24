FROM node:22-alpine
WORKDIR /app
COPY package.json .
RUN npm install --omit=dev && npm cache clean --force
COPY index.js .
# Usuario sin privilegios de la imagen oficial (uid 1000): el Deployment exige runAsNonRoot.
USER node
EXPOSE 3004
CMD ["node", "index.js"]

# 2026 - Disenador asignatura: Ignacio A. Pastenet M.
