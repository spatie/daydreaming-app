"""Generate public notes from a maintained version entry or actual Git changes."""
import argparse
import html
from pathlib import Path
import re
import subprocess


def generate(repo: Path, version: str, previous: str | None) -> str:
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("Expected numeric major.minor.patch version")
    maintained = repo / "docs/releases" / f"{version}.md"
    if maintained.is_file():
        return maintained.read_text().strip() + "\n"
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    if previous:
        if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", previous):
            raise ValueError("Invalid previous release tag")
        subprocess.run(["git", "merge-base", "--is-ancestor", previous, revision], cwd=repo, check=True)
        revision = f"{previous}..{revision}"
    subjects = subprocess.check_output(["git", "log", "--no-merges", "--format=%s", revision],
                                       cwd=repo, text=True).splitlines()
    entries = []
    for subject in subjects:
        subject = re.sub(r"^(feat|fix|perf|refactor|chore|docs|test|build|ci)(\([^)]*\))?!?:\s*", "", subject)
        subject = re.sub(r"\s*\(#\d+\)$", "", subject).strip()
        if not subject or subject.lower().startswith(("release v", "bump version", "merge ")):
            continue
        subject = re.sub(r"https?://\S+", "", subject).strip()
        subject = subject.replace("\u2014", ",").replace("\u2013", "-")
        if subject and subject not in entries:
            entries.append(subject)
    if not entries:
        raise ValueError("No maintained notes or changes found. Refusing invented notes")
    return f"# Daydreaming {version}\n\n" + "\n".join(f"- {text}" for text in entries) + "\n"


def render(markdown: str) -> str:
    """Render the small changelog format without accepting raw HTML."""
    blocks, items = [], []

    def flush():
        if items:
            blocks.append("<ul>" + "".join(f"<li>{html.escape(item)}</li>" for item in items) + "</ul>")
            items.clear()

    for line in markdown.splitlines():
        if line.startswith("- "):
            items.append(line[2:])
        else:
            flush()
            if line.startswith("# "):
                blocks.append(f"<h2>{html.escape(line[2:])}</h2>")
            elif line.strip():
                blocks.append(f"<p>{html.escape(line)}</p>")
    flush()
    return "\n".join(blocks) + "\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--previous-tag")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    notes = generate(repo, args.version, args.previous_tag)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "notes.md").write_text(notes)
    (args.output / "notes.html").write_text(render(notes))
