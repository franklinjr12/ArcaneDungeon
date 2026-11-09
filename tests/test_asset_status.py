#!/usr/bin/env python3
"""AD-189: tests for tools/asset_status.py. Local only, stdlib unittest; writes only under temp dirs."""
import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
sys.path.insert(0, str(ROOT / 'scripts'))

import asset_status as ast  # noqa: E402
import gen_placeholder_audio as gen  # noqa: E402

PRESETS = 'exclude_filter="docs/*, tools/*, scripts/*, tests/*, .godot/*"\nencryption_exclude_filters=""\n'

CUES = {
    'unstealable_priority': 3,
    'cues': {
        'sfx.cast.fire': {'stream': 'res://assets/audio/sfx/sfx_cast_fire.wav', 'bus': 'SFX', 'priority': 1},
        'sfx.silent': {'stream': 'res://assets/audio/sfx/sfx_silent.wav', 'bus': 'SFX', 'priority': 1},
    },
}

RULES = {
    'schema_version': 1,
    'rules': [
        {'glob': 'art/export/fnt/arc_fnt_m5x7.*', 'status': 'third-party', 'licence': 'CC0 (test)',
         'credit': 'm5x7 font', 'note': ''},
        {'glob': 'art/export/fnt/arc_fnt_digits_3x5.*', 'status': 'third-party', 'licence': '',
         'credit': '', 'note': 'origin and licence not recorded in the repo; owner to confirm'},
        {'glob': 'art/export/*', 'status': 'placeholder', 'licence': 'Project-original (Arcane Studio)',
         'credit': '', 'note': 'first art pass'},
    ],
}


def write(root, rel, data):
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data if isinstance(data, bytes) else data.encode('utf-8'))


class AssetStatusTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.root = self.tmp / 'repo'
        write(self.root, 'export_presets.cfg', PRESETS)
        write(self.root, 'game/audio/audio_cues_v1.json', json.dumps(CUES))
        write(self.root, 'art/export/fnt/arc_fnt_m5x7.png', b'font')
        write(self.root, 'art/export/fnt/arc_fnt_digits_3x5.png', b'font')
        write(self.root, 'art/export/hero.png', b'art')
        write(self.root, 'assets/audio/sfx/sfx_cast_fire.wav', gen.wav_bytes(gen.render('sfx.cast.fire'), False))
        write(self.root, 'assets/audio/sfx/sfx_unmapped.wav', b'RIFF')
        write(self.root, 'misc/loose.png', b'art')
        write(self.root, 'docs/demo/shot.png', b'doc')
        write(self.root, 'tools/tool_icon.png', b'tool')
        write(self.root, '.godot/cache.png', b'cache')
        write(self.root, 'art/export/hero.png.import', 'import')
        self.rules_path = self.tmp / 'rules.json'
        write(self.tmp, 'rules.json', json.dumps(RULES))

    def tearDown(self):
        self._tmp.cleanup()

    def records(self):
        rules = ast.load_rules(self.rules_path)
        return {r['file']: r for r in ast.build_records(self.root, rules, ast.export_excludes(self.root / 'export_presets.cfg'))}

    def run_main(self, *args):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return ast.main(['--root', str(self.root), '--rules', str(self.rules_path)] + list(args))

    def test_excluded_dirs_skipped(self):
        self.assertEqual(sorted(self.records()), [
            'art/export/fnt/arc_fnt_digits_3x5.png',
            'art/export/fnt/arc_fnt_m5x7.png',
            'art/export/hero.png',
            'assets/audio/sfx/sfx_cast_fire.wav',
            'assets/audio/sfx/sfx_unmapped.wav',
            'misc/loose.png',
        ])

    def test_first_rule_wins(self):
        rec = self.records()['art/export/fnt/arc_fnt_m5x7.png']
        self.assertEqual((rec['status'], rec['licence'], rec['type']), ('third-party', 'CC0 (test)', 'font'))
        self.assertEqual(self.records()['art/export/hero.png']['status'], 'placeholder')

    def test_third_party_with_licence_not_flagged(self):
        self.assertFalse(self.records()['art/export/fnt/arc_fnt_m5x7.png']['flagged'])

    def test_third_party_without_licence_flagged(self):
        rec = self.records()['art/export/fnt/arc_fnt_digits_3x5.png']
        self.assertEqual(rec['status'], 'third-party')
        self.assertTrue(rec['flagged'])
        self.assertIn('owner to confirm', rec['note'])

    def test_no_rule_is_unknown_and_flagged(self):
        rec = self.records()['misc/loose.png']
        self.assertEqual(rec['status'], 'unknown')
        self.assertTrue(rec['flagged'])

    def test_unknown_audio_flagged(self):
        rec = self.records()['assets/audio/sfx/sfx_unmapped.wav']
        self.assertEqual((rec['status'], rec['type']), ('third-party', 'audio'))
        self.assertTrue(rec['flagged'])

    def test_generated_audio_is_placeholder_cc0(self):
        rec = self.records()['assets/audio/sfx/sfx_cast_fire.wav']
        self.assertEqual(rec['status'], 'placeholder')
        self.assertTrue(rec['licence'].startswith('CC0'))
        self.assertFalse(rec['flagged'])

    def test_check_passes_after_generation_and_fails_after_edit(self):
        out = self.tmp / 'ASSET_STATUS.md'
        self.assertEqual(self.run_main('--output', str(out)), 0)
        self.assertEqual(self.run_main('--output', str(out), '--check'), 0)
        out.write_text(out.read_text(encoding='utf-8') + 'edited\n', encoding='utf-8')
        self.assertEqual(self.run_main('--output', str(out), '--check'), 1)

    def test_check_writes_nothing_and_fails_when_missing(self):
        out = self.tmp / 'missing' / 'ASSET_STATUS.md'
        self.assertEqual(self.run_main('--output', str(out), '--check'), 1)
        self.assertFalse(out.exists())

    def test_two_renders_identical(self):
        first, second = self.tmp / 'a.md', self.tmp / 'b.md'
        self.assertEqual(self.run_main('--output', str(first)), 0)
        self.assertEqual(self.run_main('--output', str(second)), 0)
        self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_pr_notes_prints_sections_and_writes_nothing(self):
        out = self.tmp / 'ASSET_STATUS.md'
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            self.assertEqual(ast.main(['--root', str(self.root), '--rules', str(self.rules_path),
                                       '--output', str(out), '--pr-notes']), 0)
        text = buf.getvalue()
        self.assertIn('## Flagged: needs licence or origin', text)
        self.assertIn('## Game-art list', text)
        self.assertNotIn('## All files', text)
        self.assertFalse(out.exists())

    def test_real_rules_file_loads(self):
        self.assertTrue(ast.load_rules(ROOT / 'tools' / 'asset_status_rules.json'))


if __name__ == '__main__':
    unittest.main()
