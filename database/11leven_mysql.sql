-- =============================================================
-- 11LEVEN - ESQUEMA RELACIONAL PARA MYSQL 8
-- =============================================================
-- Este archivo crea la estructura de la base de datos. No inserta
-- selecciones, jugadores ni partidos; esos datos se cargan desde
-- poblacion_mundial_2026.sql y los scripts del backend.
--
-- utf8mb4 permite almacenar correctamente nombres internacionales,
-- tildes y otros caracteres. La intercalación unicode_ci realiza
-- comparaciones de texto sin distinguir mayúsculas y minúsculas.
CREATE DATABASE IF NOT EXISTS `11leven` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `11leven`;

-- =============================================================
-- LIMPIEZA DEL ESQUEMA ANTERIOR
-- =============================================================
-- Se desactivan temporalmente las comprobaciones de claves foráneas
-- para poder eliminar las tablas respetando sus dependencias.
-- ADVERTENCIA: ejecutar este bloque elimina todos los datos existentes.
SET FOREIGN_KEY_CHECKS = 0;
-- Primero se eliminan las vistas porque dependen de las tablas.
DROP VIEW IF EXISTS vista_administrador_datos;
DROP VIEW IF EXISTS vista_usuario_final;
-- Las tablas hijas se eliminan antes que sus tablas padre.
DROP TABLE IF EXISTS notificacion;
DROP TABLE IF EXISTS alineacion_jugador;
DROP TABLE IF EXISTS alineacion;
DROP TABLE IF EXISTS usuario;
DROP TABLE IF EXISTS jugador;
DROP TABLE IF EXISTS partido;
DROP TABLE IF EXISTS seleccion;
SET FOREIGN_KEY_CHECKS = 1;

-- =============================================================
-- TABLA PARTIDO
-- =============================================================
-- Almacena la información general de cada encuentro.
-- Por decisión del modelo original, PARTIDO no contiene las columnas
-- id_seleccion_local ni id_seleccion_visitante. Los participantes se
-- obtienen recorriendo PARTIDO -> ALINEACION -> SELECCION mediante JOIN.
CREATE TABLE partido (
  -- Identificador interno generado automáticamente.
  id_partido INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  -- Fecha y hora local registradas para el encuentro.
  fecha DATE NOT NULL,
  hora TIME NOT NULL,
  -- Lugar, etapa del torneo y situación actual del partido.
  estadio VARCHAR(100) NOT NULL,
  fase_torneo VARCHAR(50) NOT NULL,
  estado_partido VARCHAR(20) NOT NULL,
  -- Impide guardar estados diferentes de los contemplados por el sistema.
  CONSTRAINT chk_partido_estado CHECK (estado_partido IN ('Programado','En curso','Finalizado','Suspendido')),
  -- No puede repetirse un encuentro en el mismo lugar y momento.
  CONSTRAINT uq_partido_fecha_hora_estadio UNIQUE (fecha,hora,estadio),
  -- Facilita búsquedas y ordenamientos del calendario por fecha.
  INDEX idx_partido_fecha (fecha)
) ENGINE=InnoDB;

-- =============================================================
-- TABLA SELECCION
-- =============================================================
-- Registra cada selección participante y el grupo al que pertenece.
CREATE TABLE seleccion (
  id_seleccion INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(80) NOT NULL,
  -- La bandera es opcional y puede contener una ruta local o una URL.
  bandera VARCHAR(255) NULL,
  grupo_fifa CHAR(1) NOT NULL,
  CONSTRAINT uq_seleccion_nombre UNIQUE (nombre)
) ENGINE=InnoDB;

-- =============================================================
-- TABLA JUGADOR
-- =============================================================
-- Contiene la información habitual del jugador. Su participación en
-- un partido concreto se guarda posteriormente en alineacion_jugador.
CREATE TABLE jugador (
  id_jugador INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(100) NOT NULL,
  dorsal SMALLINT UNSIGNED NOT NULL,
  -- Posición habitual: Portero, Defensa, Mediocampista o Delantero.
  posicion VARCHAR(30) NOT NULL,
  -- Cada jugador pertenece a una sola selección.
  id_seleccion INT UNSIGNED NOT NULL,
  CONSTRAINT fk_jugador_seleccion FOREIGN KEY (id_seleccion) REFERENCES seleccion(id_seleccion),
  -- Dentro de una selección no puede repetirse un dorsal.
  CONSTRAINT uq_jugador_dorsal_seleccion UNIQUE (id_seleccion,dorsal),
  CONSTRAINT uq_jugador_nombre_seleccion UNIQUE (id_seleccion,nombre),
  -- El dorsal debe corresponder a un número deportivo válido.
  CONSTRAINT chk_jugador_dorsal CHECK (dorsal BETWEEN 1 AND 99),
  INDEX idx_jugador_seleccion (id_seleccion)
) ENGINE=InnoDB;

-- =============================================================
-- TABLA USUARIO
-- =============================================================
-- Almacena los usuarios que pueden suscribirse a avisos internos.
-- Esta tabla no reemplaza la contraseña administrativa de backend/.env.
CREATE TABLE usuario (
  id_usuario INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(100) NOT NULL,
  correo VARCHAR(150) NOT NULL,
  idioma VARCHAR(30) NOT NULL,
  -- TRUE indica que el usuario desea recibir avisos de alineaciones.
  notificaciones BOOLEAN NOT NULL,
  -- Un mismo correo no puede registrarse más de una vez.
  CONSTRAINT uq_usuario_correo UNIQUE (correo)
) ENGINE=InnoDB;

-- =============================================================
-- TABLA ALINEACION
-- =============================================================
-- Relaciona una selección con un partido. Cada partido puede tener dos
-- alineaciones, una por cada selección participante.
CREATE TABLE alineacion (
  id_alineacion INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_partido INT UNSIGNED NOT NULL,
  id_seleccion INT UNSIGNED NOT NULL,
  -- Ejemplos: 4-3-3, 4-2-3-1 o 3-5-2.
  formacion_tactica VARCHAR(20) NOT NULL,
  tipo VARCHAR(20) NOT NULL,
  -- Referencia a la procedencia de la información y su publicación.
  fuente VARCHAR(150) NOT NULL,
  fecha_publicacion TIMESTAMP NOT NULL,
  estado VARCHAR(20) NOT NULL,
  -- Claves foráneas que permiten conocer partido y selección mediante JOIN.
  CONSTRAINT fk_alineacion_partido FOREIGN KEY (id_partido) REFERENCES partido(id_partido),
  CONSTRAINT fk_alineacion_seleccion FOREIGN KEY (id_seleccion) REFERENCES seleccion(id_seleccion),
  -- Evita dos alineaciones de la misma selección para el mismo partido.
  CONSTRAINT uq_alineacion_partido_seleccion UNIQUE (id_partido,id_seleccion),
  -- Limitación de valores permitidos para estado y tipo.
  CONSTRAINT chk_alineacion_estado CHECK (estado IN ('Probable','Confirmada')),
  CONSTRAINT chk_alineacion_tipo CHECK (tipo IN ('Titular','Alternativa')),
  -- Acelera consultas de alineaciones probables o confirmadas.
  INDEX idx_alineacion_estado (estado)
) ENGINE=InnoDB;

-- =============================================================
-- TABLA ASOCIATIVA ALINEACION_JUGADOR
-- =============================================================
-- Representa la convocatoria de un jugador para una alineación concreta.
-- Aquí se diferencia su posición habitual de la posición que ocupó en
-- ese partido y se indica si fue titular o suplente.
CREATE TABLE alineacion_jugador (
  id_alineacion INT UNSIGNED NOT NULL,
  id_jugador INT UNSIGNED NOT NULL,
  rol VARCHAR(15) NOT NULL,
  -- Puede variar respecto a jugador.posicion para un partido específico.
  posicion_cancha VARCHAR(30) NULL,
  -- Solo se utiliza cuando un suplente ingresa durante el encuentro.
  minuto_cambio SMALLINT UNSIGNED NULL,
  -- La clave compuesta evita repetir un jugador en una alineación.
  PRIMARY KEY (id_alineacion,id_jugador),
  CONSTRAINT fk_aj_alineacion FOREIGN KEY (id_alineacion) REFERENCES alineacion(id_alineacion),
  CONSTRAINT fk_aj_jugador FOREIGN KEY (id_jugador) REFERENCES jugador(id_jugador),
  CONSTRAINT chk_aj_rol CHECK (rol IN ('Titular','Suplente')),
  CONSTRAINT chk_aj_minuto_solo_suplente CHECK (minuto_cambio IS NULL OR rol='Suplente'),
  CONSTRAINT chk_aj_minuto_rango CHECK (minuto_cambio IS NULL OR minuto_cambio BETWEEN 1 AND 120),
  INDEX idx_aj_jugador (id_jugador)
) ENGINE=InnoDB;

-- =============================================================
-- TABLA NOTIFICACION
-- =============================================================
-- Guarda los avisos internos generados al confirmar una alineación.
-- El backend crea un aviso Pendiente para cada usuario que tenga
-- activada la opción usuario.notificaciones.
CREATE TABLE notificacion (
  id_notificacion INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  fecha_envio TIMESTAMP NOT NULL,
  estado VARCHAR(20) NOT NULL,
  -- Usuario receptor y alineación que originó el aviso.
  id_usuario INT UNSIGNED NOT NULL,
  id_alineacion INT UNSIGNED NOT NULL,
  CONSTRAINT fk_notificacion_usuario FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario),
  CONSTRAINT fk_notificacion_alineacion FOREIGN KEY (id_alineacion) REFERENCES alineacion(id_alineacion),
  CONSTRAINT uq_notificacion_usuario_alineacion UNIQUE (id_usuario,id_alineacion),
  -- Permite controlar el ciclo de procesamiento del aviso.
  CONSTRAINT chk_notificacion_estado CHECK (estado IN ('Pendiente','Enviada','Fallida'))
) ENGINE=InnoDB;

-- REGLAS DE NEGOCIO
--
-- Regla 1: cada partido debe tener exactamente dos alineaciones oficiales,
-- una por cada selección. Esta regla se valida desde el backend, porque durante
-- la creación debe permitirse el estado temporal en el que solo existe una.
--
-- Regla 2: una selección solo puede registrar una alineación por partido.
-- Se garantiza con uq_alineacion_partido_seleccion.
--
-- Regla 3: un jugador solo puede aparecer una vez dentro de una misma alineación.
-- Se garantiza con la llave primaria compuesta (id_alineacion, id_jugador).
--
-- Regla 4: el estado de una alineación únicamente puede ser Probable o Confirmada.
-- Se garantiza con chk_alineacion_estado.
--
-- Regla 5: el rol del jugador únicamente puede ser Titular o Suplente.
-- Se garantiza con chk_aj_rol.
--
-- Regla 6: el minuto de cambio solo podrá registrarse para jugadores suplentes
-- que ingresaron al partido y debe estar entre 1 y 120.
-- Se garantiza con chk_aj_minuto_solo_suplente y chk_aj_minuto_rango.
--
-- Regla 7: el correo del usuario debe ser único.
-- Se garantiza con uq_usuario_correo.
--
-- Regla 8: el dorsal de un jugador no puede repetirse dentro de una misma selección
-- y debe estar entre 1 y 99.
-- Se garantiza con uq_jugador_dorsal_seleccion y chk_jugador_dorsal.

-- =============================================================
-- VISTA PARA EL ADMINISTRADOR
-- =============================================================
-- Reúne en una consulta los datos del partido, alineación, selección
-- y jugadores pertenecientes a esa selección. Incluye campos internos
-- y metadatos como fuente y fecha de publicación.
CREATE VIEW vista_administrador_datos AS
SELECT p.id_partido,p.fecha AS fecha_partido,p.hora AS hora_partido,p.estadio,p.fase_torneo,p.estado_partido,
 a.id_alineacion,a.formacion_tactica,a.tipo AS tipo_alineacion,a.fuente,a.fecha_publicacion,a.estado AS estado_alineacion,
 s.id_seleccion,s.nombre AS nombre_seleccion,s.grupo_fifa,s.bandera,
 j.id_jugador,j.nombre AS nombre_jugador,j.dorsal,j.posicion AS posicion_habitual
FROM partido p JOIN alineacion a ON a.id_partido=p.id_partido
JOIN seleccion s ON s.id_seleccion=a.id_seleccion JOIN jugador j ON j.id_seleccion=s.id_seleccion;

-- =============================================================
-- VISTA PARA EL USUARIO FINAL
-- =============================================================
-- Presenta información semejante a la vista administrativa, pero omite
-- la fuente y la fecha de publicación para ofrecer una salida simplificada.
CREATE VIEW vista_usuario_final AS
SELECT p.id_partido,p.fecha AS fecha_partido,p.hora AS hora_partido,p.estadio,p.fase_torneo,p.estado_partido,
 a.id_alineacion,a.formacion_tactica,a.tipo AS tipo_alineacion,a.estado AS estado_alineacion,
 s.id_seleccion,s.nombre AS nombre_seleccion,s.grupo_fifa,s.bandera,
 j.id_jugador,j.nombre AS nombre_jugador,j.dorsal,j.posicion AS posicion_habitual
FROM partido p JOIN alineacion a ON a.id_partido=p.id_partido
JOIN seleccion s ON s.id_seleccion=a.id_seleccion JOIN jugador j ON j.id_seleccion=s.id_seleccion;
