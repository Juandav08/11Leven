const db = require('../config/db');

const definitions = {
  selecciones: { table: 'seleccion', id: 'id_seleccion', fields: ['nombre', 'bandera', 'grupo_fifa'] },
  jugadores: { table: 'jugador', id: 'id_jugador', fields: ['nombre', 'dorsal', 'posicion', 'id_seleccion'] },
  partidos: { table: 'partido', id: 'id_partido', fields: ['fecha', 'hora', 'estadio', 'fase_torneo', 'estado_partido'] },
  usuarios: { table: 'usuario', id: 'id_usuario', fields: ['nombre', 'correo', 'idioma', 'notificaciones'] }
};
const allowedStages = new Set([...'ABCDEFGHIJKL'].map((group) => `Fase de grupos - Grupo ${group}`).concat(['Dieciseisavos de final','Octavos de final','Cuartos de final','Semifinal','Partido por el tercer puesto','Final','Partido de prueba / Otro']));

function valuesFor(body, fields) {
  return fields.map((field) => body[field]);
}

function missingFields(body, fields) {
  return fields.filter((field) => body[field] === undefined || body[field] === '');
}

function validationProblem(resource, body) {
  if (resource === 'jugadores' && !['Portero', 'Defensa', 'Mediocampista', 'Delantero'].includes(body.posicion)) return 'Selecciona una posición válida para el jugador.';
  if (resource === 'partidos' && !allowedStages.has(body.fase_torneo)) return 'Selecciona una fase del torneo válida.';
  return null;
}

async function duplicateProblem(connection, resource, body, currentId = 0) {
  let sql; let params; let message;
  if (resource === 'selecciones') {
    sql = 'SELECT id_seleccion FROM seleccion WHERE LOWER(TRIM(nombre))=LOWER(TRIM(?)) AND id_seleccion<>? LIMIT 1';
    params = [body.nombre, currentId]; message = 'Ya existe una selección con ese nombre.';
  } else if (resource === 'jugadores') {
    sql = 'SELECT id_jugador FROM jugador WHERE id_seleccion=? AND (LOWER(TRIM(nombre))=LOWER(TRIM(?)) OR dorsal=?) AND id_jugador<>? LIMIT 1';
    params = [body.id_seleccion, body.nombre, body.dorsal, currentId]; message = 'Esa selección ya tiene un jugador con el mismo nombre o dorsal.';
  } else if (resource === 'partidos') {
    sql = 'SELECT id_partido FROM partido WHERE fecha=? AND hora=? AND LOWER(TRIM(estadio))=LOWER(TRIM(?)) AND id_partido<>? LIMIT 1';
    params = [body.fecha, body.hora, body.estadio, currentId]; message = 'Ya existe un partido en la misma fecha, hora y estadio.';
  } else if (resource === 'usuarios') {
    sql = 'SELECT id_usuario FROM usuario WHERE LOWER(TRIM(correo))=LOWER(TRIM(?)) AND id_usuario<>? LIMIT 1';
    params = [body.correo, currentId]; message = 'Ya existe un usuario con ese correo.';
  } else return null;
  const [rows] = await connection.execute(sql, params);
  return rows.length ? message : null;
}

function controller(resource) {
  const { table, id, fields } = definitions[resource];
  return {
    async list(req, res, next) {
      try {
        const where = resource === 'jugadores' && req.query.id_seleccion ? ' WHERE id_seleccion = ?' : '';
        const params = where ? [req.query.id_seleccion] : [];
        const [rows] = await db.execute(`SELECT * FROM ${table}${where} ORDER BY ${id} DESC`, params);
        res.json(rows);
      } catch (error) { next(error); }
    },
    async get(req, res, next) {
      try {
        const [rows] = await db.execute(`SELECT * FROM ${table} WHERE ${id} = ?`, [req.params.id]);
        if (!rows.length) return res.status(404).json({ error: 'Registro no encontrado.' });
        res.json(rows[0]);
      } catch (error) { next(error); }
    },
    async create(req, res, next) {
      try {
        const missing = missingFields(req.body, fields);
        if (missing.length) return res.status(400).json({ error: `Faltan campos: ${missing.join(', ')}` });
        const problem = validationProblem(resource, req.body); if (problem) return res.status(400).json({ error: problem });
        const duplicate = await duplicateProblem(db, resource, req.body); if (duplicate) return res.status(409).json({ error: duplicate });
        const placeholders = fields.map(() => '?').join(', ');
        const [result] = await db.execute(`INSERT INTO ${table} (${fields.join(', ')}) VALUES (${placeholders})`, valuesFor(req.body, fields));
        res.status(201).json({ [id]: result.insertId, ...req.body });
      } catch (error) { next(error); }
    },
    async update(req, res, next) {
      try {
        const missing = missingFields(req.body, fields);
        if (missing.length) return res.status(400).json({ error: `Faltan campos: ${missing.join(', ')}` });
        const problem = validationProblem(resource, req.body); if (problem) return res.status(400).json({ error: problem });
        const duplicate = await duplicateProblem(db, resource, req.body, Number(req.params.id)); if (duplicate) return res.status(409).json({ error: duplicate });
        const set = fields.map((field) => `${field} = ?`).join(', ');
        const [result] = await db.execute(`UPDATE ${table} SET ${set} WHERE ${id} = ?`, [...valuesFor(req.body, fields), req.params.id]);
        if (!result.affectedRows) { await connection.rollback(); return res.status(404).json({ error: 'Registro no encontrado.' }); }
        res.json({ [id]: Number(req.params.id), ...req.body });
      } catch (error) { next(error); }
    },
    async remove(req, res, next) {
      const connection = await db.getConnection();
      try {
        await connection.beginTransaction();
        if (resource === 'selecciones') {
          await connection.execute('DELETE n FROM notificacion n JOIN alineacion a ON a.id_alineacion=n.id_alineacion WHERE a.id_seleccion=?', [req.params.id]);
          await connection.execute('DELETE aj FROM alineacion_jugador aj JOIN alineacion a ON a.id_alineacion=aj.id_alineacion WHERE a.id_seleccion=?', [req.params.id]);
          await connection.execute('DELETE FROM alineacion WHERE id_seleccion=?', [req.params.id]);
          await connection.execute('DELETE FROM jugador WHERE id_seleccion=?', [req.params.id]);
        } else if (resource === 'jugadores') {
          await connection.execute('DELETE FROM alineacion_jugador WHERE id_jugador=?', [req.params.id]);
        } else if (resource === 'partidos') {
          await connection.execute('DELETE n FROM notificacion n JOIN alineacion a ON a.id_alineacion=n.id_alineacion WHERE a.id_partido=?', [req.params.id]);
          await connection.execute('DELETE aj FROM alineacion_jugador aj JOIN alineacion a ON a.id_alineacion=aj.id_alineacion WHERE a.id_partido=?', [req.params.id]);
          await connection.execute('DELETE FROM alineacion WHERE id_partido=?', [req.params.id]);
        } else if (resource === 'usuarios') {
          await connection.execute('DELETE FROM notificacion WHERE id_usuario=?', [req.params.id]);
        }
        const [result] = await connection.execute(`DELETE FROM ${table} WHERE ${id} = ?`, [req.params.id]);
        if (!result.affectedRows) return res.status(404).json({ error: 'Registro no encontrado.' });
        await connection.commit();
        res.status(204).end();
      } catch (error) { await connection.rollback(); next(error); } finally { connection.release(); }
    }
  };
}

module.exports = controller;
