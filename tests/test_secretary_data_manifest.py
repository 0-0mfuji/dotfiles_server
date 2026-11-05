import importlib.machinery
import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / 'scripts/secretary-data-manifest'
loader = importlib.machinery.SourceFileLoader('secretary_data_export', str(path))
spec = importlib.util.spec_from_loader(loader.name, loader)
export = importlib.util.module_from_spec(spec)
loader.exec_module(export)


class ExportTests(unittest.TestCase):
    def test_only_local_data_is_selected(self):
        for path in ('data/study/input.pdf', 'books/cache/metadata.json', 'state/progress.json'):
            self.assertTrue(export.selected(path), path)
        for path in ('.env', 'data/private/.env.local', 'data/study/.venv/bin/python', 'data/script.py',
                     'study/unpublished.py', 'data/study/work/yomitoku-venv/bin/python', 'data/private/credentials.json', '../outside', 'abeto-copy/package.json'):
            self.assertFalse(export.selected(path), path)
