from pathlib import Path

path = Path(__file__).resolve().parents[1] / 'lib' / 'main.dart'
text = path.read_text(encoding='utf-8')
start = text.find('Future<void> _confirmAndOpenLink(')
end = text.find('Future<void> _showMessageActions(', start if start >= 0 else 0)
if start >= 0 and end > start:
    text = text[:start] + text[end:]
path.write_text(text, encoding='utf-8')
print('Removed superseded link confirmation helper')
