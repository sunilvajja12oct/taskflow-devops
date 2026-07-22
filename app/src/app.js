const express = require('express');
const { Pool } = require('pg');
const client = require('prom-client');

const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: false }));

// Pool reads PGHOST/PGPORT/PGUSER/PGPASSWORD/PGDATABASE from the environment.
const pool = new Pool();

client.collectDefaultMetrics();

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
});

const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
});

app.use((req, res, next) => {
  const start = process.hrtime.bigint();
  res.on('finish', () => {
    const route = req.route ? req.route.path : req.path;
    const seconds = Number(process.hrtime.bigint() - start) / 1e9;
    const labels = { method: req.method, route, status_code: res.statusCode };
    httpRequestDuration.observe(labels, seconds);
    httpRequestsTotal.inc(labels);
  });
  next();
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
});

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
  await pool.query(`
    CREATE TABLE IF NOT EXISTS contacts (
      id SERIAL PRIMARY KEY,
      name TEXT NOT NULL,
      email TEXT NOT NULL,
      purpose TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `);
}

function escapeHtml(str) {
  return String(str).replace(/[&<>"']/g, c => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));
}

function page(title, body) {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)} · TaskFlow</title>
<style>
  :root { color-scheme: light dark; }
  * { box-sizing: border-box; }
  body {
    margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
    background: #f3f5f8; color: #16222c; padding: 32px 16px;
    font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
  }
  @media (prefers-color-scheme: dark) { body { background: #10161d; color: #eaf1f7; } }
  .card {
    width: 100%; max-width: 480px; background: #fff; border-radius: 10px;
    box-shadow: 0 1px 3px rgba(20,30,40,.08), 0 10px 30px rgba(20,30,40,.10);
    padding: 34px 32px;
  }
  @media (prefers-color-scheme: dark) { .card { background: #1a232c; box-shadow: 0 10px 30px rgba(0,0,0,.4); } }
  h1 { font-size: 22px; margin: 0 0 6px; }
  p.lede { color: #5a6b78; margin: 0 0 24px; font-size: 15px; }
  @media (prefers-color-scheme: dark) { p.lede { color: #9fb2c1; } }
  label { display: block; font-size: 13px; font-weight: 600; margin: 16px 0 6px; }
  input, textarea {
    width: 100%; padding: 10px 12px; font-size: 15px; border-radius: 6px;
    border: 1px solid #c7d0d8; font-family: inherit; background: #fff; color: inherit;
  }
  @media (prefers-color-scheme: dark) { input, textarea { background: #10161d; border-color: #3a4753; } }
  textarea { min-height: 90px; resize: vertical; }
  button {
    margin-top: 22px; width: 100%; padding: 12px; font-size: 15px; font-weight: 700;
    border: none; border-radius: 6px; background: #2a78d6; color: #fff; cursor: pointer;
  }
  button:hover { background: #2266bd; }
  .error {
    background: rgba(227,73,72,.1); border: 1px solid rgba(227,73,72,.4); color: #b23231;
    padding: 10px 14px; border-radius: 6px; font-size: 14px; margin-bottom: 8px;
  }
  a { color: #2a78d6; }
  table { width: 100%; border-collapse: collapse; font-size: 14px; }
  th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid #e1e6ea; vertical-align: top; }
  @media (prefers-color-scheme: dark) { th, td { border-color: #2a343d; } }
  th { color: #5a6b78; font-size: 12px; text-transform: uppercase; letter-spacing: .04em; }
  .foot { margin-top: 18px; font-size: 13px; color: #5a6b78; }
  @media (prefers-color-scheme: dark) { .foot { color: #9fb2c1; } }
</style>
</head>
<body>
  <div class="card">${body}</div>
</body>
</html>`;
}

function contactFormPage(opts) {
  opts = opts || {};
  const v = opts.values || {};
  const errorHtml = opts.error
    ? `<div class="error">${escapeHtml(opts.error)}</div>`
    : '';
  return page('Get in touch', `
    <h1>Get in touch</h1>
    <p class="lede">Tell us who you are and what you need — we'll follow up by email.</p>
    ${errorHtml}
    <form method="POST" action="/contact">
      <label for="name">Full name</label>
      <input id="name" name="name" type="text" required value="${escapeHtml(v.name || '')}">
      <label for="email">Email</label>
      <input id="email" name="email" type="email" required value="${escapeHtml(v.email || '')}">
      <label for="purpose">What can we help you with?</label>
      <textarea id="purpose" name="purpose" required>${escapeHtml(v.purpose || '')}</textarea>
      <button type="submit">Submit</button>
    </form>
    <p class="foot"><a href="/contact/submissions">View past submissions</a></p>
  `);
}

function contactThanksPage() {
  return page('Thank you', `
    <h1>Thanks — we've got it</h1>
    <p class="lede">Your submission was received and saved. We'll be in touch by email.</p>
    <p class="foot"><a href="/contact">Submit another</a> &middot; <a href="/contact/submissions">View past submissions</a></p>
  `);
}

function contactSubmissionsPage(rows) {
  const body = rows.length
    ? `<table>
        <thead><tr><th>#</th><th>Name</th><th>Email</th><th>Purpose</th><th>Submitted</th></tr></thead>
        <tbody>
          ${rows.map(r => `<tr>
            <td>${r.id}</td>
            <td>${escapeHtml(r.name)}</td>
            <td>${escapeHtml(r.email)}</td>
            <td>${escapeHtml(r.purpose)}</td>
            <td>${new Date(r.created_at).toISOString().replace('T', ' ').slice(0, 16)} UTC</td>
          </tr>`).join('')}
        </tbody>
      </table>`
    : `<p class="lede">No submissions yet.</p>`;
  return page('Submissions', `
    <h1>Submissions</h1>
    <p class="lede">${rows.length} received so far.</p>
    ${body}
    <p class="foot"><a href="/contact">&larr; Back to form</a></p>
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

app.get('/contact', (req, res) => {
  res.type('html').send(contactFormPage());
});

app.post('/contact', async (req, res) => {
  const name = (req.body.name || '').trim();
  const email = (req.body.email || '').trim();
  const purpose = (req.body.purpose || '').trim();

  if (!name || !email || !purpose || !email.includes('@')) {
    return res.status(400).type('html').send(contactFormPage({
      error: 'Please fill in your name, a valid email, and your purpose.',
      values: { name, email, purpose },
    }));
  }

  await pool.query(
    'INSERT INTO contacts (name, email, purpose) VALUES ($1, $2, $3)',
    [name, email, purpose]
  );
  res.type('html').send(contactThanksPage());
});

app.get('/contact/submissions', async (req, res) => {
  const { rows } = await pool.query(
    'SELECT id, name, email, purpose, created_at FROM contacts ORDER BY id DESC'
  );
  res.type('html').send(contactSubmissionsPage(rows));
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
