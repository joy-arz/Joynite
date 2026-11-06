#!/usr/bin/env python3
"""Exercise the actual application model against isolated storage and providers."""
import pathlib, subprocess, tempfile
root = pathlib.Path(__file__).resolve().parents[1]
subprocess.run(['swift', 'build', '--package-path', str(root), '--product', 'JoyniteValidation'], check=True)
binpath = pathlib.Path(subprocess.check_output(['swift', 'build', '--package-path', str(root), '--show-bin-path'], text=True).strip())
objects = sorted((binpath / 'JoyniteCore.build').glob('*.o')) + sorted((binpath / 'ZIPFoundation.build').glob('*.o'))
if not objects:
    raise SystemExit('Swift core object files are unavailable')
with tempfile.TemporaryDirectory(prefix='joynite-model-validation-') as temporary:
    executable = pathlib.Path(temporary) / 'JoyniteModelValidation'
    subprocess.run(['swiftc', '-parse-as-library', '-I', str(binpath / 'Modules'), '-o', str(executable), str(root / 'Tests/JoyniteModelTests/Validation.swift'), str(root / 'Sources/Joynite/LibraryModel.swift'), *map(str, objects), '-lz'], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=60)
