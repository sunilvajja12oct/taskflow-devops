const express = require('express');
const { Pool } = require('pg');

const app = express();
app.use(express.json());

// Pool reads PGHOST/PGPORT/PGUSER/PGPASSWORD/PGDATABASE from the environment.
const pool = new Pool();

async function waitForDb(retries = 20, delayMs = 3000) {
  for (let i = 0; i < retries; i++) {
    try {
      await pool.query('SELECT 1');
      return;
    } catch (err) {
      console.log(`Waiting for database (attempt ${i + 1}/${retries}): ${err.message}`);
      await new Promise(r => setTimeout(r, delayMs));
    }
  }
  throw new Error('Database never became reachable');
}

async function migrate() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS tasks (
      id SERIAL PRIMARY KEY,
      title TEXT NOT NULL,
      done BOOLEAN NOT NULL DEFAULT false
    )
  `);
}

app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok' });
  } catch (err) {
    res.status(503).json({ status: 'db unreachable' });
  }
});

app.get('/tasks', async (req, res) => {
  const { rows } = await pool.query('SELECT id, title, done FROM tasks ORDER BY id');
  res.json(rows);
});

app.post('/tasks', async (req, res) => {
  const { rows } = await pool.query(
    'INSERT INTO tasks (title, done) VALUES ($1, false) RETURNING id, title, done',
    [req.body.title]
  );
  res.status(201).json(rows[0]);
});

app.patch('/tasks/:id', async (req, res) => {
  const id = parseInt(req.params.id);
  const { rows } = await pool.query(
    'UPDATE tasks SET title = COALESCE($2, title), done = COALESCE($3, done) WHERE id = $1 RETURNING id, title, done',
    [id, req.body.title ?? null, req.body.done ?? null]
  );
  if (rows.length === 0) return res.status(404).json({ error: 'not found' });
  res.json(rows[0]);
});

const port = process.env.PORT || 3000;

waitForDb()
  .then(migrate)
  .then(() => {
    app.listen(port, () => console.log(`TaskFlow listening on ${port}`));
  })
  .catch(err => {
    console.error('Startup failed:', err);
    process.exit(1);
  });
