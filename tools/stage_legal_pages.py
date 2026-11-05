#!/usr/bin/env python3
"""Stage public legal pages into the exact web deployment directory."""
import argparse
from pathlib import Path
import shutil


def stage(destination: Path) -> None:
    source = Path(__file__).resolve().parents[1] / 'docs/appstore'
    destination.mkdir(parents=True, exist_ok=True)
    for name in ('privacy.html', 'support.html'):
        shutil.copy2(source / name, destination / name)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=Path)
    stage(parser.parse_args().destination)
