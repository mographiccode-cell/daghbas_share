import { scanSkill } from '@estelwalks/agent-threat-scanner'

let input = ''
for await (const chunk of process.stdin) input += chunk
const payload = JSON.parse(input || '{}')
const files = Array.isArray(payload.files) ? payload.files : [{ path: payload.path || 'content.txt', content: payload.content || '' }]
const report = await scanSkill({ mode: payload.mode || 'quick', files })
process.stdout.write(JSON.stringify(report))
