"""Markdown link checker -- extracts and validates links from .md files."""

import re
import sys
from pathlib import Path
from urllib.parse import urlparse


def extract_links(markdown: str) -> list[dict]:
    """Extract all markdown links [text](url) from content."""
    pattern = r"\[([^\]]*)\]\(([^)]*)\)"
    matches = re.findall(pattern, markdown)
    links = []
    for text, url in matches:
        links.append({
            "text": text,
            "url": url,
            "is_external": url.startswith("http"),
            # BUG 1: should check for anchor links starting with #
            "is_anchor": url.startswith("/"),
        })
    return links


def validate_local_link(link: str, base_dir: Path) -> bool:
    """Check if a local file link points to an existing file."""
    if link.startswith("#"):
        return True
    # Strip anchor from path
    path = link.split("#")[0]
    # BUG 2: resolves relative to cwd instead of base_dir
    target = Path(path)
    return target.exists()


def check_file(filepath: str) -> list[dict]:
    """Check all links in a markdown file. Returns list of issues."""
    path = Path(filepath)
    if not path.exists():
        return [{"error": f"File not found: {filepath}"}]

    content = path.read_text()
    links = extract_links(content)
    issues = []

    for link in links:
        if link["is_external"]:
            parsed = urlparse(link["url"])
            if not parsed.scheme or not parsed.netloc:
                issues.append({
                    "text": link["text"],
                    "url": link["url"],
                    "issue": "Malformed URL",
                })
        elif not link["is_anchor"]:
            if not validate_local_link(link["url"], path.parent):
                issues.append({
                    "text": link["text"],
                    "url": link["url"],
                    "issue": "Broken local link",
                })

    # BUG 3: returns links instead of issues
    return links


def main():
    if len(sys.argv) < 2:
        print("Usage: python link_checker.py <file.md> [file2.md ...]")
        sys.exit(1)

    total_issues = 0
    for filepath in sys.argv[1:]:
        issues = check_file(filepath)
        if issues:
            print(f"\n{filepath}:")
            for issue in issues:
                if "error" in issue:
                    print(f"  ERROR: {issue['error']}")
                else:
                    print(f"  [{issue['text']}]({issue['url']}) -- {issue['issue']}")
            total_issues += len(issues)

    if total_issues == 0:
        print("All links OK.")
    else:
        print(f"\n{total_issues} issue(s) found.")
        sys.exit(1)


if __name__ == "__main__":
    main()
