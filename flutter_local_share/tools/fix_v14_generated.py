from pathlib import Path

main_path = Path(__file__).resolve().parents[1] / 'lib' / 'main.dart'
text = main_path.read_text(encoding='utf-8')
text = text.replace(
    "      if (target == null || !mounted) return;\n      setState(() => selectedPeerId = target!.deviceId);\n      for (final file in shared.files) {\n        try {\n          await service.sendFile(target!, file);",
    "      if (target == null || !mounted) return;\n      final selectedTarget = target;\n      setState(() => selectedPeerId = selectedTarget.deviceId);\n      for (final file in shared.files) {\n        try {\n          await service.sendFile(selectedTarget, file);",
)
text = text.replace(
    "          await service.sendChat(target!, sharedText);",
    "          await service.sendChat(selectedTarget, sharedText);",
)
main_path.write_text(text, encoding='utf-8')
print('Normalized LocalShare 1.4 generated source')
