// Carga de la demo de escalado (k6). Cada usuario virtual pide sin pausa el
// catalogo por el ALB (GET /api/products: frontend -> get-products -> RDS) y la
// portada (GET /). Rampa de subida, meseta y bajada; los valores llegan con -e:
//   k6 run -e BASE_URL=http://<DNS del ALB> -e VUS=100 -e MESETA=6m carga.js
// Normalmente lo lanza freshbox-demo.
import http from 'k6/http';
import { check } from 'k6';

const BASE_URL = __ENV.BASE_URL;
const VUS = Number(__ENV.VUS || 100);

if (!BASE_URL) {
  throw new Error('Falta BASE_URL (http://<DNS del ALB>)');
}

export const options = {
  stages: [
    { duration: __ENV.SUBIDA || '2m', target: VUS },
    { duration: __ENV.MESETA || '6m', target: VUS },
    { duration: __ENV.BAJADA || '1m', target: 0 },
  ],
  summaryTrendStats: ['avg', 'p(95)', 'max'],
};

export default function () {
  const api = http.get(`${BASE_URL}/api/products`, { tags: { ruta: 'api' } });
  check(api, { 'GET /api/products 200': (r) => r.status === 200 });

  const portada = http.get(`${BASE_URL}/`, { tags: { ruta: 'portada' } });
  check(portada, { 'GET / 200': (r) => r.status === 200 });
}
