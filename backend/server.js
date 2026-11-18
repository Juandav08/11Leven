const path = require('path');
const fs = require('fs');
const express = require('express');
const crudRoutes = require('./routes/crudRoutes');
const alineacionesRoutes = require('./routes/alineacionesRoutes');
const notificacionesRoutes = require('./routes/notificacionesRoutes');
const publicNotifications = require('./controllers/publicNotificationsController');
const adminAuth = require('./middleware/adminAuth');

const app = express();
const frontend = path.join(__dirname, '..', 'frontend');
app.use(express.json());
app.post('/api/admin/login', adminAuth.login);
app.post('/api/admin/logout', adminAuth.logout);
app.get('/api/admin/session', (req, res) => res.json({ authenticated: Boolean(adminAuth.currentSession(req)) }));
app.use('/api/selecciones', protectWrites, crudRoutes('selecciones'));
app.use('/api/jugadores', protectWrites, crudRoutes('jugadores'));
app.use('/api/partidos', protectWrites, crudRoutes('partidos'));
app.get('/api/usuarios-publicos', publicNotifications.users);
app.get('/api/notificaciones-usuario/:id', publicNotifications.forUser);
app.use('/api/alineaciones', protectWrites, alineacionesRoutes);
app.use('/api/usuarios', protectWrites, crudRoutes('usuarios'));
app.use('/api/notificaciones', protectWrites, notificacionesRoutes);
app.get('/api/resultados', (_req, res, next) => {
  fs.readFile(path.join(__dirname, 'data', 'fifaResults.json'), 'utf8', (error, content) => {
    if (error) return error.code === 'ENOENT' ? res.json([]) : next(error);
    try { res.json(JSON.parse(content)); } catch (parseError) { next(parseError); }
  });
});
app.get('/admin.html', (req, res) => {
  if (!adminAuth.currentSession(req)) return res.redirect('/login.html');
  res.sendFile(path.join(frontend, 'admin.html'));
});
app.use(express.static(frontend));

app.use('/api', (_req, res) => res.status(404).json({ error: 'Ruta no encontrada.' }));
app.use((error, _req, res, _next) => {
  console.error(error);
  if (error.code === 'ER_DUP_ENTRY') return res.status(409).json({ error: 'El registro ya existe o viola una restricción única.' });
  if (error.code === 'ER_ROW_IS_REFERENCED_2') return res.status(409).json({ error: 'No se puede eliminar: existen registros asociados.' });
  if (error.code === 'ECONNREFUSED' || error.code === 'ER_BAD_DB_ERROR') return res.status(503).json({ error: 'No fue posible conectar con MySQL. Revisa la configuración de backend/.env.' });
  res.status(error.status || 500).json({ error: error.message || 'Error interno.' });
});

const port = Number(process.env.PORT || 3000);
app.listen(port, () => console.log(`11Leven disponible en http://localhost:${port}`));

function protectWrites(req, res, next) {
  if (req.method === 'GET') return next();
  adminAuth.requireAdmin(req, res, next);
}
