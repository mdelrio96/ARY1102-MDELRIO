FROM nginx:1.28-alpine
# Valores para EKS (namespace freshbox); docker-compose.yml los cambia para la red local.
ENV NGINX_RESOLVER=kube-dns.kube-system.svc.cluster.local \
    SVC_SUFFIX=.freshbox.svc.cluster.local
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
COPY index.html /usr/share/nginx/html/
COPY css/ /usr/share/nginx/html/css/
COPY js/ /usr/share/nginx/html/js/
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]

# 2026 - Disenador asignatura: Ignacio A. Pastenet M.
