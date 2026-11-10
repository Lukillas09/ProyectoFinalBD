// Única URL base de la API. En local es el mismo origen a través de Nginx
// (/api/* -> api:8000), así que no hace falta CORS. En la Etapa 8 este archivo
// se puede generar al desplegar con la URL pública.
window.BODEGAS_CONFIG = { apiBase: "/api" };
