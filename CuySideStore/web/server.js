//
//  server.js
//  CuySideStore — Web UI local
//
//  Interfaz web local que envuelve la tool CLI cuysidestore:
//    - Subir IPAs y ejecutar el pipeline completo
//    - Ver la salida de consola en tiempo real (SSE)
//    - Descargar los artefactos generados
//    - Ver certificados, doctor y estado del servidor de pruebas
//
//  ⚠️ SOLO PARA USO LOCAL — no exponer a la red
//

const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { spawn } = require('child_process');

const app = express();
const PORT = process.env.PORT || 4567;

// ─── Rutas del proyecto ────────────────────────────────────────
const PROJECT_DIR = path.resolve(__dirname, '..');
const CLI = path.join(PROJECT_DIR, 'scripts', 'cuysidestore');
const UPLOADS_DIR = path.join(__dirname, 'uploads');
const OUTPUT_DIR = path.join(PROJECT_DIR, 'output');

fs.mkdirSync(UPLOADS_DIR, { recursive: true });
fs.mkdirSync(OUTPUT_DIR, { recursive: true });

// ─── Middleware ────────────────────────────────────────────────
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

const upload = multer({
    storage: multer.diskStorage({
        destination: UPLOADS_DIR,
        filename: (req, file, cb) => {
            // Sanitizar nombre: solo caracteres seguros
            const safe = file.originalname.replace(/[^a-zA-Z0-9._-]/g, '_');
            cb(null, `${Date.now()}_${safe}`);
        }
    }),
    limits: { fileSize: 500 * 1024 * 1024 } // 500 MB
});

// ─── Helper: ejecutar CLI con streaming de salida ─────────────
// Cada job tiene un buffer de líneas que los clientes SSE leen
const jobs = new Map();
let jobCounter = 0;

function runCli(args, label) {
    const jobId = ++jobCounter;
    const job = {
        id: jobId,
        label: label || args.join(' '),
        status: 'running',
        lines: [],
        startedAt: new Date().toISOString(),
        finishedAt: null,
        exitCode: null
    };
    jobs.set(jobId, job);

    const proc = spawn('bash', [CLI, ...args], {
        cwd: PROJECT_DIR
    });

    const push = (data) => {
        // Convertir output a líneas y agregarlas al buffer
        const text = data.toString();
        for (const line of text.split('\n')) {
            if (line.length > 0 || text.endsWith('\n')) {
                job.lines.push(line);
            }
        }
        // Limitar buffer (evitar memoria infinita)
        if (job.lines.length > 5000) {
            job.lines = job.lines.slice(-5000);
        }
    };

    proc.stdout.on('data', push);
    proc.stderr.on('data', push);

    proc.on('close', (code) => {
        job.status = code === 0 ? 'completed' : 'failed';
        job.exitCode = code;
        job.finishedAt = new Date().toISOString();
        console.log(`[job ${jobId}] ${job.status} (exit ${code})`);
    });

    proc.on('error', (err) => {
        job.status = 'failed';
        job.exitCode = -1;
        job.lines.push(`❌ Error al ejecutar: ${err.message}`);
        job.finishedAt = new Date().toISOString();
    });

    return { jobId, job };
}

// ─── API ───────────────────────────────────────────────────────

// Health check
app.get('/api/health', (req, res) => {
    res.json({
        ok: true,
        project: 'CuySideStore Web UI',
        version: '1.0.0',
        time: new Date().toISOString()
    });
});

// Doctor — verificar dependencias
app.get('/api/doctor', (req, res) => {
    const { jobId } = runCli(['doctor'], 'doctor');
    res.json({ jobId });
});

// Certificados disponibles
app.get('/api/certs', (req, res) => {
    const { jobId } = runCli(['certs'], 'certs');
    res.json({ jobId });
});

// Estado de un job (polling)
app.get('/api/jobs/:id', (req, res) => {
    const job = jobs.get(parseInt(req.params.id));
    if (!job) {
        return res.status(404).json({ error: 'Job no encontrado' });
    }
    res.json({
        id: job.id,
        label: job.label,
        status: job.status,
        exitCode: job.exitCode,
        startedAt: job.startedAt,
        finishedAt: job.finishedAt,
        lineCount: job.lines.length
    });
});

// Salida completa de un job
app.get('/api/jobs/:id/output', (req, res) => {
    const job = jobs.get(parseInt(req.params.id));
    if (!job) {
        return res.status(404).json({ error: 'Job no encontrado' });
    }
    res.json({ lines: job.lines });
});

// Stream en vivo de un job (SSE)
app.get('/api/jobs/:id/stream', (req, res) => {
    const job = jobs.get(parseInt(req.params.id));
    if (!job) {
        return res.status(404).json({ error: 'Job no encontrado' });
    }

    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');

    let sentLines = 0;
    const interval = setInterval(() => {
        // Enviar líneas nuevas
        while (sentLines < job.lines.length) {
            const line = job.lines[sentLines];
            // Sanitizar para SSE (los \n dentro de una línea romperían el stream)
            const safe = line.replace(/\n/g, '\\n');
            res.write(`data: ${JSON.stringify({ line: safe })}\n\n`);
            sentLines++;
        }

        // Si el job terminó y enviamos todo, cerrar
        if (job.status !== 'running' && sentLines >= job.lines.length) {
            res.write(`data: ${JSON.stringify({ done: true, status: job.status, exitCode: job.exitCode })}\n\n`);
            clearInterval(interval);
            res.end();
        }
    }, 300);

    // Cleanup si el cliente se desconecta
    req.on('close', () => clearInterval(interval));
});

// Subir IPA y ejecutar pipeline
app.post('/api/pipeline', upload.single('ipa'), (req, res) => {
    if (!req.file) {
        return res.status(400).json({ error: 'No se subió ningún IPA' });
    }

    const ipaPath = req.file.path;
    const cert = req.body.cert || ''; // opcional

    const args = ['pipeline', ipaPath];
    if (cert) {
        args.push('--cert', cert);
    }

    const { jobId, job } = runCli(args, `pipeline: ${req.file.originalname}`);
    res.json({ jobId, filename: req.file.originalname });
});

// Comandos individuales sobre un IPA subido
app.post('/api/analyze', upload.single('ipa'), (req, res) => {
    if (!req.file) return res.status(400).json({ error: 'No se subió ningún IPA' });
    const { jobId } = runCli(['analyze', req.file.path], `analyze: ${req.file.originalname}`);
    res.json({ jobId, filename: req.file.originalname });
});

app.post('/api/resign', upload.single('ipa'), (req, res) => {
    if (!req.file) return res.status(400).json({ error: 'No se subió ningún IPA' });
    const cert = req.body.cert;
    if (!cert) return res.status(400).json({ error: 'Certificado requerido (--cert)' });

    const { jobId } = runCli(['resign', req.file.path, '--cert', cert], `resign: ${req.file.originalname}`);
    res.json({ jobId, filename: req.file.originalname });
});

app.post('/api/inject', upload.single('ipa'), (req, res) => {
    if (!req.file) return res.status(400).json({ error: 'No se subió ningún IPA' });
    const dylib = req.body.dylib || path.join(PROJECT_DIR, 'test-dylibs', 'hook_license.dylib');

    const { jobId } = runCli(['inject', req.file.path, '--dylib', dylib], `inject: ${req.file.originalname}`);
    res.json({ jobId, filename: req.file.originalname });
});

app.post('/api/ents', upload.single('ipa'), (req, res) => {
    if (!req.file) return res.status(400).json({ error: 'No se subió ningún IPA' });
    const preset = req.body.preset || 'desarrollo';

    const { jobId } = runCli(['ents', req.file.path, '--preset', preset], `ents: ${req.file.originalname}`);
    res.json({ jobId, filename: req.file.originalname });
});

// Listar artefactos generados en output/
app.get('/api/artifacts', (req, res) => {
    try {
        if (!fs.existsSync(OUTPUT_DIR)) {
            return res.json({ artifacts: [] });
        }
        const files = fs.readdirSync(OUTPUT_DIR)
            .filter(f => !f.startsWith('.'))
            .map(f => {
                const stat = fs.statSync(path.join(OUTPUT_DIR, f));
                return {
                    name: f,
                    size: stat.size,
                    sizeHuman: formatBytes(stat.size),
                    modified: stat.mtime.toISOString(),
                    isIpa: f.endsWith('.ipa')
                };
            })
            .sort((a, b) => b.modified.localeCompare(a.modified));
        res.json({ artifacts: files });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Descargar un artefacto
app.get('/api/artifacts/:name/download', (req, res) => {
    const name = path.basename(req.params.name); // prevenir path traversal
    const filePath = path.join(OUTPUT_DIR, name);

    if (!fs.existsSync(filePath)) {
        return res.status(404).json({ error: 'Artefacto no encontrado' });
    }
    res.download(filePath, name);
});

// Eliminar un artefacto
app.delete('/api/artifacts/:name', (req, res) => {
    const name = path.basename(req.params.name);
    const filePath = path.join(OUTPUT_DIR, name);

    if (!fs.existsSync(filePath)) {
        return res.status(404).json({ error: 'Artefacto no encontrado' });
    }
    fs.unlinkSync(filePath);
    res.json({ ok: true });
});

// Listar IPAs subidos
app.get('/api/uploads', (req, res) => {
    try {
        const files = fs.readdirSync(UPLOADS_DIR)
            .filter(f => f.endsWith('.ipa'))
            .map(f => {
                const stat = fs.statSync(path.join(UPLOADS_DIR, f));
                return {
                    name: f,
                    originalName: f.replace(/^\d+_/, ''),
                    size: stat.size,
                    sizeHuman: formatBytes(stat.size),
                    uploaded: stat.mtime.toISOString()
                };
            })
            .sort((a, b) => b.uploaded.localeCompare(a.uploaded));
        res.json({ uploads: files });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Ejecutar comando sobre un IPA ya subido (sin re-subir)
app.post('/api/run', (req, res) => {
    const { command, filename, cert, preset, dylib } = req.body;

    if (!command || !filename) {
        return res.status(400).json({ error: 'command y filename requeridos' });
    }

    // Buscar el archivo subido (puede tener prefijo timestamp)
    const uploads = fs.readdirSync(UPLOADS_DIR).filter(f => f.endsWith('.ipa'));
    const target = uploads.find(f => f === filename || f.replace(/^\d+_/, '') === filename);

    if (!target) {
        return res.status(404).json({ error: `IPA no encontrado: ${filename}` });
    }

    const ipaPath = path.join(UPLOADS_DIR, target);
    let args;

    switch (command) {
        case 'analyze':
            args = ['analyze', ipaPath];
            break;
        case 'resign':
            if (!cert) return res.status(400).json({ error: 'cert requerido para resign' });
            args = ['resign', ipaPath, '--cert', cert];
            break;
        case 'inject':
            args = ['inject', ipaPath, '--dylib', dylib || path.join(PROJECT_DIR, 'test-dylibs', 'hook_license.dylib')];
            break;
        case 'ents':
            args = ['ents', ipaPath, '--preset', preset || 'desarrollo'];
            break;
        case 'pipeline':
            args = cert ? ['pipeline', ipaPath, '--cert', cert] : ['pipeline', ipaPath];
            break;
        default:
            return res.status(400).json({ error: `Comando desconocido: ${command}` });
    }

    const { jobId } = runCli(args, `${command}: ${target}`);
    res.json({ jobId });
});

// ─── Helper ────────────────────────────────────────────────────
function formatBytes(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
}

// ─── Iniciar ───────────────────────────────────────────────────
app.listen(PORT, () => {
    console.log('');
    console.log('═════════════════════════════════════════════════════════════');
    console.log('  CuySideStore — Web UI');
    console.log('═════════════════════════════════════════════════════════════');
    console.log(`  Abre en tu navegador: http://localhost:${PORT}`);
    console.log('');
    console.log('  ⚠️ SOLO USO LOCAL — no exponer este servidor a la red');
    console.log('═════════════════════════════════════════════════════════════');
    console.log('');
});