"""Lectura y validación de la configuración de la API."""

from dataclasses import dataclass, field
from os import environ


class ConfigurationError(RuntimeError):
    """Indica que una variable de entorno obligatoria es inválida."""


def _required(name: str) -> str:
    value = environ.get(name)
    if value is None or value == "":
        raise ConfigurationError(
            f"La variable de entorno {name} es obligatoria."
        )
    return value


def _positive_int(name: str, default: int, maximum: int | None = None) -> int:
    raw_value = environ.get(name, str(default))

    try:
        value = int(raw_value)
    except ValueError as error:
        raise ConfigurationError(
            f"La variable de entorno {name} debe ser un número entero."
        ) from error

    if value < 1 or (maximum is not None and value > maximum):
        allowed_range = f"entre 1 y {maximum}" if maximum else "mayor que cero"
        raise ConfigurationError(
            f"La variable de entorno {name} debe ser {allowed_range}."
        )

    return value


# Valores de sslmode que acepta libpq. En Render se usa "require" (Etapa 8, R4):
# la conexión a la base va cifrada aunque viaje por la red privada.
SSLMODES = ("disable", "allow", "prefer", "require", "verify-ca", "verify-full")


def _sslmode() -> str:
    value = environ.get("DB_SSLMODE", "prefer")
    if value not in SSLMODES:
        raise ConfigurationError(
            f"DB_SSLMODE debe ser uno de: {', '.join(SSLMODES)}."
        )
    return value


def cors_origins_desde_entorno() -> tuple[str, ...]:
    """Orígenes permitidos por CORS (Etapa 8, R11), desde CORS_ORIGINS.

    Vacía o ausente: sin CORS, como en local, donde el front y la API
    comparten origen a través de nginx. Nunca se acepta "*": sólo el origen
    público del front puede llamar a la API desde un navegador.
    """

    raw_value = environ.get("CORS_ORIGINS", "")
    origins = tuple(o.strip() for o in raw_value.split(",") if o.strip())
    for origin in origins:
        valido = origin.startswith("https://") or origin.startswith("http://localhost")
        if not valido or origin.endswith("/") or "*" in origin:
            raise ConfigurationError(
                "CORS_ORIGINS acepta orígenes https://... o http://localhost..., "
                f"sin barra final ni comodines: {origin!r}."
            )
    return origins


@dataclass(frozen=True, slots=True)
class Settings:
    """Configuración necesaria para crear el pool de PostgreSQL."""

    db_host: str
    db_port: int
    db_name: str
    db_user: str
    db_password: str = field(repr=False)
    db_pool_min_size: int = 1
    db_pool_max_size: int = 5
    db_pool_timeout_seconds: int = 3
    db_connect_timeout_seconds: int = 3
    db_sslmode: str = "prefer"

    @classmethod
    def from_environment(cls) -> "Settings":
        settings = cls(
            db_host=_required("DB_HOST"),
            db_port=_positive_int("DB_PORT", 5432, maximum=65535),
            db_name=_required("DB_NAME"),
            db_user=_required("DB_USER"),
            db_password=_required("DB_PASSWORD"),
            db_pool_min_size=_positive_int("DB_POOL_MIN_SIZE", 1),
            db_pool_max_size=_positive_int("DB_POOL_MAX_SIZE", 5),
            db_pool_timeout_seconds=_positive_int(
                "DB_POOL_TIMEOUT_SECONDS", 3
            ),
            db_connect_timeout_seconds=_positive_int(
                "DB_CONNECT_TIMEOUT_SECONDS", 3
            ),
            db_sslmode=_sslmode(),
        )

        if settings.db_pool_min_size > settings.db_pool_max_size:
            raise ConfigurationError(
                "DB_POOL_MIN_SIZE no puede superar DB_POOL_MAX_SIZE."
            )

        return settings

    def connection_kwargs(self) -> dict[str, str | int | bool]:
        """Devuelve parámetros discretos; evita construir o registrar una URL."""

        return {
            "host": self.db_host,
            "port": self.db_port,
            "dbname": self.db_name,
            "user": self.db_user,
            "password": self.db_password,
            "connect_timeout": self.db_connect_timeout_seconds,
            "sslmode": self.db_sslmode,
            "application_name": "bodegas_api",
            "autocommit": True,
        }
