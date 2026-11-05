"""Legal pages must survive a normal Flutter Pages publish."""
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class LegalPagesTests(unittest.TestCase):
    def test_stages_both_real_legal_pages_in_build_output(self):
        with tempfile.TemporaryDirectory() as output:
            result = subprocess.run(
                ['python3', str(ROOT / 'tools/stage_legal_pages.py'), output],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            for name in ('privacy.html', 'support.html'):
                self.assertEqual(
                    (pathlib.Path(output) / name).read_bytes(),
                    (ROOT / 'docs/appstore' / name).read_bytes(),
                )

    def test_ci_stages_pages_before_publish(self):
        workflow = (ROOT / '.github/workflows/build.yml').read_text()
        self.assertIn('python3 tools/stage_legal_pages.py build/web', workflow)
        self.assertLess(workflow.index('python3 tools/stage_legal_pages.py build/web'),
                        workflow.index('publish_dir: build/web'))


if __name__ == '__main__':
    unittest.main()
