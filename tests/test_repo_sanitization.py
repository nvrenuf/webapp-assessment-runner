from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLIENT_STRINGS = [
    "capital" + "link",
    "community" + "capital",
    "community" + "-" + "capital",
    "community" + "ct",
    "Capital" + "Link",
    "Community" + " " + "Capital",
]
SKIP_PARTS = {".git", ".pytest_cache", "__pycache__"}
SKIP_ROOTS = {"assessments", "evidence", "reports", "logs"}
TEXT_SUFFIXES = {".md", ".sh", ".py", ".txt", ".yaml", ".yml", ".example", ".env", ".tmpl", ".ini", ".json", ""}


def iter_repo_text_files():
    for path in ROOT.rglob("*"):
        rel = path.relative_to(ROOT)
        if not path.is_file():
            continue
        if rel.parts[0] in SKIP_ROOTS or any(part in SKIP_PARTS for part in rel.parts):
            continue
        if path.suffix in TEXT_SUFFIXES or path.name in {".gitignore", "Makefile", "AGENTS.md"}:
            yield path


def test_no_client_specific_strings_in_repo_files() -> None:
    offenders = []
    for path in iter_repo_text_files():
        text = path.read_text(encoding="utf-8", errors="ignore")
        for needle in CLIENT_STRINGS:
            if needle in text:
                offenders.append(f"{path.relative_to(ROOT)}: {needle}")
    assert offenders == []


def test_docs_alphabet_removed() -> None:
    assert not (ROOT / "docs" / "alphabet.md").exists()
