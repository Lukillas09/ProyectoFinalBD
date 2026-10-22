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
            "application_name": "bodegas_api",
            "autocommit": True,
        }
